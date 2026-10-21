from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, Field, ConfigDict, field_validator

Money = Annotated[Decimal, Field(max_digits=14, decimal_places=2, allow_inf_nan=False)]


class Item(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=1, max_length=300)
    quantity: Decimal = Field(gt=0, max_digits=14, decimal_places=6, allow_inf_nan=False)
    unit_price: Money = Field(ge=0)
    amount: Money = Field(ge=0)
    discount: Money = Field(default=Decimal("0.00"), ge=0)
    vat: str | None = None

    @field_validator("discount")
    @classmethod
    def valid_discount(cls, value, info):
        if value > info.data.get("amount", value):
            raise ValueError("Discount exceeds item amount")
        return value


class Receipt(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[Item] = Field(default_factory=list, max_length=1000)
    total: Money | None = Field(default=None, ge=0)
    raw_text: str = Field(default="", max_length=100000)
    warnings: list[str] = Field(default_factory=list)


class Person(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class Assignment(BaseModel):
    item_index: int = Field(ge=0)
    person_ids: list[int] = Field(min_length=1)


class Settlement(BaseModel):
    assignments: list[Assignment]
