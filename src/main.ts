import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // อ่านค่า PORT จาก environment variable, ถ้าไม่มีให้ใช้ 3000
  await app.listen(process.env.PORT || 3000);
}
bootstrap()