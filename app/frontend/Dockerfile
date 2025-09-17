# Stage 1: Build the Vue.js application ####
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Hardened Nginx static server ####
FROM nginx:alpine
WORKDIR /
COPY nginx.conf /etc/nginx/nginx.conf
RUN adduser -D -H -u 10001 webuser \
	&& rm -rf /usr/share/nginx/html/*
COPY --from=build /app/dist /usr/share/nginx/html
RUN mkdir -p /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp \
	&& mkdir -p /var/log/nginx \
	&& chown -R 10001:0 /tmp /var/log/nginx /usr/share/nginx/html
USER webuser
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]