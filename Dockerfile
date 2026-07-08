# Build stage - สำหรับ development และ testing
FROM node:22-alpine AS builder

# กำหนด Working Directory ภายใน Container
WORKDIR /app

# Copy ไฟล์ package.json และ package-lock.json
COPY package*.json ./

# ติดตั้ง Dependencies
RUN npm install

# Copy โค้ดทั้งหมดในโปรเจกต์
COPY . .

# ล้าง dist เก่าทิ้งก่อน build
RUN rm -rf dist

# Build NestJS Application
RUN npm run build

# Production stage - สำหรับ production deployment
FROM node:22-alpine AS production

# กำหนด Working Directory ภายใน Container
WORKDIR /app

# Copy package files
COPY package*.json ./

# ติดตั้งเฉพาะ production dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy โค้ดที่ compiled แล้วจาก builder stage
COPY --from=builder /app/dist ./dist

# กำหนด Port ที่ Container จะทำงาน
EXPOSE 3000

# Set environment variable
ENV NODE_ENV=production

# คำสั่งสำหรับรัน NestJS Application (ใช้ compiled JavaScript)
CMD ["node", "dist/main"]
