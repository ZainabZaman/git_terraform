from fastapi import FastAPI
from dotenv import load_dotenv
import os

# Load environment variables from .env file
load_dotenv()

app = FastAPI()

@app.get("/")
def read_root():
    secret_value = os.getenv("MY_SECRET", "secret-not-found")
    return {"message": f"The secret is: {secret_value}"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)