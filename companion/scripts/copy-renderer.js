const fs = require("node:fs");
const path = require("node:path");
const destDir = path.join(__dirname, "..", "dist", "renderer");
fs.mkdirSync(destDir, { recursive: true });
fs.copyFileSync(
  path.join(__dirname, "..", "renderer", "index.html"),
  path.join(destDir, "index.html"),
);
