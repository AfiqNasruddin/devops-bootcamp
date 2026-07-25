# --- build stage ---
FROM node:20-alpine AS build
WORKDIR /app
# Copy manifests first so the install layer is cached until deps actually change.
COPY package*.json ./
RUN npm ci
# Now the source; changes here do not bust the install cache above.
COPY . .
RUN npm run build

# --- runtime stage ---
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
