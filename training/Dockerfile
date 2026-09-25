FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY training/requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt
COPY training /app/training
ENTRYPOINT ["python", "-m", "training.entrypoint"]
