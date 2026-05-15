import { startServer } from "./codex-proxy/src/index.ts";

const port = Number.parseInt(process.env.PORT || "8089", 10);
const handle = await startServer({ host: "127.0.0.1", port });

let closing = false;
async function shutdown() {
  if (closing) {
    return;
  }
  closing = true;
  await handle.close();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

setInterval(() => {}, 60 * 60 * 1000);
