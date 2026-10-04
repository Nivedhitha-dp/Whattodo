# Runs LifeFlow locally in Docker (Windows has no native jac installer yet).
# Usage (PowerShell):
#   $env:GEMINI_API_KEY = "..."      # and/or $env:ANTHROPIC_API_KEY = "..."
#   .\run-local.ps1
# Then open http://localhost:8000

docker rm -f lifeflow 2>$null | Out-Null
docker run -d --name lifeflow --user root -p 8000:8000 `
  -e GEMINI_API_KEY=$env:GEMINI_API_KEY `
  -e ANTHROPIC_API_KEY=$env:ANTHROPIC_API_KEY `
  -v "${PSScriptRoot}:/app" -v lifeflow_jac:/app/.jac -w /app `
  --entrypoint bash jaseci/jaclang -c "jac install && jac run --host 0.0.0.0 --port 8000" | Out-Null
Write-Host "Starting LifeFlow... follow logs with: docker logs -f lifeflow"
Write-Host "Open http://localhost:8000 once you see 'Server ready'."
