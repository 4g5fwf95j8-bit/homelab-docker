# whisper-stt

OpenAI-compatible speech-to-text (faster-whisper under the hood) via [Speaches](https://speaches.ai).

- Model recommendation for CPU: `Systran/faster-whisper-small` (good accuracy/speed balance on 4 cores; `base` if it still feels slow)
- First transcription request downloads the model — expect a delay the first time
- Test it directly:
```
  curl -s http://localhost:8000/v1/audio/transcriptions \
    -F "file=@test.wav" \
    -F "model=Systran/faster-whisper-small"
```