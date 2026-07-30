CREATE TABLE IF NOT EXISTS receipts (
    id SERIAL PRIMARY KEY,
    store TEXT,
    purchased_at DATE,
    subtotal NUMERIC(10, 2),
    tax NUMERIC(10, 2),
    total NUMERIC(10, 2),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS receipt_items (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES receipts(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    quantity NUMERIC(10, 2) DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_receipt_items_receipt_id ON receipt_items(receipt_id);
CREATE INDEX IF NOT EXISTS idx_receipts_purchased_at ON receipts(purchased_at);
