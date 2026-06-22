import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Builds to frontend/dist, which the pipeline uploads to the $web container.
export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist" },
});
