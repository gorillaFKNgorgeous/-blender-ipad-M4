FROM python:3.13-slim
WORKDIR /app
COPY server.py store.py oauth.py ./
RUN useradd --system --uid 10001 ghostbridge && mkdir /data && chown ghostbridge /data
USER 10001
ENV BIND_HOST=0.0.0.0 PORT=8080 DATABASE_PATH=/data/ghostblender.sqlite3
EXPOSE 8080
CMD ["python", "server.py"]
