import { useEffect, useRef, useState } from "react";
import * as signalR from "@microsoft/signalr";
import { FUNCTION_BASE_URL, fetchDocuments, uploadDocument } from "./api.js";

const STATUS_ORDER = ["UPLOADED", "QUEUED", "PROCESSING", "PROCESSED", "ERROR"];

function statusClass(status) {
  if (status === "ERROR") return "badge error";
  if (status === "PROCESSED") return "badge done";
  return "badge pending";
}

function formatSize(bytes) {
  if (bytes == null) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default function App() {
  // documentId -> document record
  const [docs, setDocs] = useState({});
  const [connection, setConnection] = useState("connecting");
  const [uploading, setUploading] = useState(false);
  const [message, setMessage] = useState(null);
  const fileInput = useRef(null);

  function applyUpdate(doc) {
    if (!doc || !doc.documentId) return;
    setDocs((prev) => ({ ...prev, [doc.documentId]: { ...prev[doc.documentId], ...doc } }));
  }

  useEffect(() => {
    function refresh() {
      return fetchDocuments()
        .then((list) => {
          // Merge so we never overwrite a fresher SignalR update with a slow poll.
          setDocs((prev) => {
            const map = { ...prev };
            for (const d of list) map[d.documentId] = { ...map[d.documentId], ...d };
            return map;
          });
        })
        .catch(() => {/* API may be cold; SignalR / next poll will fill in */});
    }

    refresh();
    // Fallback poll: guarantees the UI converges even if a SignalR push is missed.
    const poll = setInterval(refresh, 4000);

    const conn = new signalR.HubConnectionBuilder()
      .withUrl(FUNCTION_BASE_URL)
      .withAutomaticReconnect()
      .configureLogging(signalR.LogLevel.Warning)
      .build();

    conn.on("statusUpdate", applyUpdate);
    conn.onreconnecting(() => setConnection("reconnecting"));
    conn.onreconnected(() => setConnection("connected"));
    conn.onclose(() => setConnection("disconnected"));

    conn
      .start()
      .then(() => setConnection("connected"))
      .catch(() => setConnection("disconnected"));

    return () => {
      clearInterval(poll);
      conn.stop();
    };
  }, []);

  async function handleUpload(event) {
    event.preventDefault();
    const file = fileInput.current?.files?.[0];
    if (!file) {
      setMessage({ type: "error", text: "Choose a file first." });
      return;
    }
    setUploading(true);
    setMessage(null);
    try {
      await uploadDocument(file);
      setMessage({ type: "ok", text: `Uploaded "${file.name}" — processing…` });
      if (fileInput.current) fileInput.current.value = "";
    } catch (err) {
      setMessage({ type: "error", text: `Upload failed: ${err.message}` });
    } finally {
      setUploading(false);
    }
  }

  const rows = Object.values(docs).sort((a, b) => (a.name || "").localeCompare(b.name || ""));

  return (
    <main className="app">
      <header>
        <h1>Document Pipeline</h1>
        <span className={`conn ${connection}`}>SignalR: {connection}</span>
      </header>

      <form className="uploader" onSubmit={handleUpload}>
        <input ref={fileInput} type="file" disabled={uploading} />
        <button type="submit" disabled={uploading}>
          {uploading ? "Uploading…" : "Upload"}
        </button>
        {message && <span className={`msg ${message.type}`}>{message.text}</span>}
      </form>

      <h2>Uploaded files</h2>
      {rows.length === 0 ? (
        <p className="empty">No files yet. Pick a file above and upload it.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>File</th>
              <th>Size</th>
              <th>Status</th>
              <th>Tags</th>
              <th>Tagged by</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((d) => (
              <tr key={d.documentId}>
                <td>{d.name}</td>
                <td>{formatSize(d.sizeBytes)}</td>
                <td>
                  <span className={statusClass(d.status)}>{d.status}</span>
                  {d.error && <div className="errmsg">{d.error}</div>}
                </td>
                <td>{(d.tags || []).join(", ") || "—"}</td>
                <td>{d.taggedBy || "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <footer>
        <small>Pipeline stages: {STATUS_ORDER.join(" → ")}</small>
      </footer>
    </main>
  );
}
