// Base URL of the Functions API, injected at build time by the pipeline as
// VITE_FUNCTION_BASE_URL (e.g. https://<func-app>.azurewebsites.net/api).
export const FUNCTION_BASE_URL = (
  import.meta.env.VITE_FUNCTION_BASE_URL || "http://localhost:7071/api"
).replace(/\/$/, "");

export async function fetchDocuments() {
  const res = await fetch(`${FUNCTION_BASE_URL}/documents`);
  if (!res.ok) throw new Error(`documents request failed: ${res.status}`);
  return res.json();
}
