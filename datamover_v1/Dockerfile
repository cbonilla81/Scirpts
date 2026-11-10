FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends rclone ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/datamover
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --system --uid 10001 --home /opt/datamover dm
COPY app ./app
RUN mkdir /state && chown -R dm:dm /state /opt/datamover
USER dm
ENV DATAMOVER_STATE=/state
EXPOSE 8080
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8080","--workers","1"]
