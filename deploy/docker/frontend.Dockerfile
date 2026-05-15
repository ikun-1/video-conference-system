# Stage 1: 构建前端
FROM node:22-alpine AS builder

WORKDIR /build
COPY video-conference-front/package.json video-conference-front/package-lock.json ./
RUN npm ci

COPY video-conference-front/ .
RUN npm run build-only

# Stage 2: Nginx 运行环境
FROM nginx:1.27-alpine

RUN rm -rf /etc/nginx/conf.d/default.conf
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /build/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
