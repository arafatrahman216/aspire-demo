.PHONY: setup dev test clean format run

setup:
	python3 -m venv .venv
	.venv/bin/pip install -e ".[dev]"

dev:
	.venv/bin/uvicorn app.main:app --reload

run:
	.venv/bin/uvicorn app.main:app

test:
	.venv/bin/pytest -v

format:
	.venv/bin/black app tests
	.venv/bin/ruff check --fix app tests

clean:
	rm -rf .pytest_cache
	rm -rf __pycache__
	find . -type d -name "__pycache__" -exec rm -rf {} +