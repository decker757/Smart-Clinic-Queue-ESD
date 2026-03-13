FROM node:22-alpine

WORKDIR /app

COPY services/doctor-service/package*.json ./
RUN npm ci

COPY services/doctor-service/tsconfig.json ./
COPY services/doctor-service/src ./src

RUN npm run build

RUN cp -r src/proto dist/proto

EXPOSE 3004

CMD ["npm", "run", "start"]