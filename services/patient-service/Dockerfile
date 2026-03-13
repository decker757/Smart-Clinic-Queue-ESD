FROM node:22-alpine
WORKDIR /app
COPY services/patient-service/package*.json ./
RUN npm ci
COPY services/patient-service/tsconfig.json ./
COPY services/patient-service/src ./src
RUN npm run build && cp -r src/proto dist/proto
EXPOSE 3007
EXPOSE 50053
CMD ["npm", "run", "start"]
