import hashlib
import json
import os
import secrets
import time
from datetime import datetime, timezone
from typing import Optional

import boto3
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import DateTime, Integer, String, create_engine, func, select, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

APP_NAME = "company-order-service"
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]
IMPORT_TOKEN_SECRET_ARN = os.environ["IMPORT_TOKEN_SECRET_ARN"]

secrets_client = boto3.client("secretsmanager")

def load_secret(arn: str) -> dict:
    value = secrets_client.get_secret_value(SecretId=arn)["SecretString"]
    return json.loads(value)

db_secret = load_secret(DB_SECRET_ARN)
db_user = db_secret["username"]
db_password = db_secret["password"]
db_host = db_secret["host"]
db_port = db_secret.get("port", 5432)
db_name = db_secret.get("dbname", "orders")

DATABASE_URL = (
    f"postgresql+psycopg://{db_user}:{db_password}"
    f"@{db_host}:{db_port}/{db_name}"
)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=1800,
    pool_size=int(os.getenv("DB_POOL_SIZE", "5")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "5")),
    connect_args={"connect_timeout": 5},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

class Base(DeclarativeBase):
    pass

class Order(Base):
    __tablename__ = "orders"

    order_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    customer_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    product_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    idempotency_key: Mapped[Optional[str]] = mapped_column(String(128), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

app = FastAPI(title=APP_NAME, version=os.getenv("APP_VERSION", "dev"))

@app.on_event("startup")
def startup():
    # Assessment-friendly bootstrap. For production use Alembic migrations.
    Base.metadata.create_all(engine)

def db_session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

class OrderCreate(BaseModel):
    customer_id: str = Field(min_length=1, max_length=128)
    product_id: str = Field(min_length=1, max_length=128)
    quantity: int = Field(gt=0, le=100000)

class OrderResponse(BaseModel):
    order_id: str
    customer_id: str
    product_id: str
    quantity: int
    status: str
    created_at: datetime
    updated_at: datetime

def to_response(o: Order) -> OrderResponse:
    return OrderResponse(
        order_id=o.order_id,
        customer_id=o.customer_id,
        product_id=o.product_id,
        quantity=o.quantity,
        status=o.status,
        created_at=o.created_at,
        updated_at=o.updated_at,
    )

def create_order(db: Session, payload: OrderCreate, idempotency_key: Optional[str] = None):
    if idempotency_key:
        existing = db.scalar(select(Order).where(Order.idempotency_key == idempotency_key))
        if existing:
            return existing

    now = datetime.now(timezone.utc)
    order = Order(
        order_id=f"ORD-{secrets.token_hex(8).upper()}",
        customer_id=payload.customer_id,
        product_id=payload.product_id,
        quantity=payload.quantity,
        status="PENDING",
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    return order

@app.get("/health")
def health():
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "reachable", "version": os.getenv("APP_VERSION", "dev")}
    except Exception:
        raise HTTPException(status_code=503, detail="database unavailable")

@app.post("/orders", response_model=OrderResponse, status_code=201)
def post_order(
    payload: OrderCreate,
    db: Session = Depends(db_session),
    x_idempotency_key: Optional[str] = Header(default=None),
):
    try:
        return to_response(create_order(db, payload, x_idempotency_key))
    except Exception:
        db.rollback()
        raise

@app.post("/internal/import-order", response_model=OrderResponse, status_code=201)
def import_order(
    payload: OrderCreate,
    db: Session = Depends(db_session),
    authorization: Optional[str] = Header(default=None),
    x_idempotency_key: Optional[str] = Header(default=None),
):
    expected = json.loads(
        secrets_client.get_secret_value(SecretId=IMPORT_TOKEN_SECRET_ARN)["SecretString"]
    )["token"]
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="unauthorized")
    supplied = authorization.split(" ", 1)[1]
    if not secrets.compare_digest(supplied, expected):
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        return to_response(create_order(db, payload, x_idempotency_key))
    except Exception:
        db.rollback()
        raise

@app.get("/orders/{order_id}", response_model=OrderResponse)
def get_order(order_id: str, db: Session = Depends(db_session)):
    order = db.get(Order, order_id)
    if not order:
        raise HTTPException(status_code=404, detail="order not found")
    return to_response(order)

@app.get("/orders", response_model=list[OrderResponse])
def list_orders(
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(db_session),
):
    orders = db.scalars(
        select(Order).order_by(Order.created_at.desc()).limit(limit)
    ).all()
    return [to_response(o) for o in orders]


class StatusUpdate(BaseModel):
    status: str = Field(pattern="^(PENDING|PROCESSING|COMPLETED|FAILED)$")

@app.patch("/internal/orders/{order_id}/status", response_model=OrderResponse)
def update_status(
    order_id: str,
    payload: StatusUpdate,
    db: Session = Depends(db_session),
    authorization: Optional[str] = Header(default=None),
):
    expected = json.loads(
        secrets_client.get_secret_value(SecretId=IMPORT_TOKEN_SECRET_ARN)["SecretString"]
    )["token"]
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="unauthorized")
    if not secrets.compare_digest(authorization.split(" ", 1)[1], expected):
        raise HTTPException(status_code=401, detail="unauthorized")
    order = db.get(Order, order_id)
    if not order:
        raise HTTPException(status_code=404, detail="order not found")
    order.status = payload.status
    order.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(order)
    return to_response(order)

@app.get("/stats")
def stats(db: Session = Depends(db_session)):
    total = db.scalar(select(func.count()).select_from(Order)) or 0
    pending = db.scalar(select(func.count()).select_from(Order).where(Order.status == "PENDING")) or 0
    completed = db.scalar(select(func.count()).select_from(Order).where(Order.status == "COMPLETED")) or 0
    failed = db.scalar(select(func.count()).select_from(Order).where(Order.status == "FAILED")) or 0
    product = db.execute(
        select(Order.product_id, func.sum(Order.quantity).label("qty"))
        .group_by(Order.product_id)
        .order_by(func.sum(Order.quantity).desc())
        .limit(1)
    ).first()
    return {
        "total_orders": total,
        "pending_orders": pending,
        "completed_orders": completed,
        "failed_orders": failed,
        "most_frequently_ordered_product": product[0] if product else None,
    }
