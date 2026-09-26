"""The shop's data, in memory."""
from dataclasses import dataclass


@dataclass
class Product:
    name: str
    price: int


@dataclass
class Order:
    id: int
    customer: str
    total: int


PRODUCTS = [Product("Mug", 120), Product("Poster", 250), Product("Tote bag", 90)]
ORDERS = [Order(1, "ada@example.com", 370), Order(2, "linus@example.com", 90)]
