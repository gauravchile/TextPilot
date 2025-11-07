from flask import Blueprint, request, jsonify
from .model import analyze_text

main_bp = Blueprint("main", __name__)

@main_bp.route("/")
def index():
    return jsonify({"message": "Welcome to TextPilot API"}), 200

@main_bp.route("/analyze", methods=["POST"])
def analyze():
    data = request.get_json(silent=True) or {}
    text = data.get("text", "")
    if not text:
        return jsonify({"error": "No text provided"}), 400
    result = analyze_text(text)
    return jsonify(result), 200

@main_bp.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

