# Multi-stage: build the React app with Node, then serve the static files with
# nginx. VITE_FUNCTION_BASE_URL is baked in at build time (Vite inlines env vars
# prefixed with VITE_ into the bundle), so it is passed as a build arg.
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ARG VITE_FUNCTION_BASE_URL
ENV VITE_FUNCTION_BASE_URL=$VITE_FUNCTION_BASE_URL
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
