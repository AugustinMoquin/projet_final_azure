# Multi-stage: build the React app with Node, then serve the static files with
# nginx. VITE_FUNCTION_BASE_URL is baked in at build time (Vite inlines env vars
# prefixed with VITE_ into the bundle), so it is passed as a build arg.
#
# BASE_REGISTRY lets the pipeline pull the base images from our own ACR (mirrored
# from Docker Hub) to avoid Docker Hub anonymous-pull rate limits during ACR
# builds. It defaults to docker.io so local `docker build` works unchanged.
ARG BASE_REGISTRY=docker.io

FROM ${BASE_REGISTRY}/library/node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ARG VITE_FUNCTION_BASE_URL
ENV VITE_FUNCTION_BASE_URL=$VITE_FUNCTION_BASE_URL
RUN npm run build

FROM ${BASE_REGISTRY}/library/nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
