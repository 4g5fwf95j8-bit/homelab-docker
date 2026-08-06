# kokoro-tts

OpenAI-compatible text-to-speech via [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI).

- Default voice: `af_heart` (warm, natural). Full voice list: `curl http://localhost:8880/v1/audio/voices`
- Test it directly:
```
  curl -s http://localhost:8880/v1/audio/speech \
    -H "Content-Type: application/json" \
    -d '{"model":"kokoro","input":"Hello, this is a test.","voice":"af_heart"}' \
    --output test.mp3
```