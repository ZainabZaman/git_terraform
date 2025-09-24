from fastapi import FastAPI
import os

app = FastAPI()


@app.get("/")
def read_root():
    secret_value = os.getenv("MY_SECRET", "secret-not-found")
    return {"message": f"The secret is: {secret_value}"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)