#!/bin/bash
# Local dev server — avoids file:// security restrictions in Chrome
# Usage: ./dev.sh
# Then open: http://localhost:8080/src/form-template.html?colleagues=Name1,Name2,Name3

echo "Starting local dev server..."
echo "Open: http://localhost:8080/src/form-template.html?colleagues=Name1,Name2,Name3"
python3 -m http.server 8080
