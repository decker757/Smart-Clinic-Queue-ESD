FROM node:22-alpine

WORKDIR /app

COPY services/auth-service/package*.json ./
RUN npm ci

COPY services/auth-service/tsconfig.json ./
COPY services/auth-service/src ./src

RUN npm run build

EXPOSE 3000

CMD ["npm", "run", "start"]
