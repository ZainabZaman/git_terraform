from fastapi import FastAPI
import os

app = FastAPI()


@app.get("/")
def read_root():
    secret_value = os.getenv("MY_SECRET", "secret-not-found")
    return {"message": f"The secret is: {secret_value}"}
