import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  getHello(): string {
    return 'Hello from NestJS Docker App!';
  }

  getHealth(): string {
    return 'OK';
  }

  // เพิ่ม method ใหม่สำหรับทดสอบ
  getInfo(): object {
    return {
      app: 'NestJS Docker App',
      version: '1.0.0',
      framework: 'NestJS 11',
      node: process.version,
      timestamp: new Date().toISOString()
    };
  }
}