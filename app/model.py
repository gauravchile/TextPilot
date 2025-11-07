from transformers import pipeline

# Load model once at startup
sentiment_pipeline = pipeline(
    "sentiment-analysis",
    model="distilbert-base-uncased-finetuned-sst-2-english"
)

def analyze_text(text: str):
    """
    Analyzes sentiment of input text using Hugging Face transformers.
    Returns: dict {label, score}
    """
    result = sentiment_pipeline(text)[0]
    return {
        "label": result["label"],
        "score": round(result["score"], 4)
    }

