import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { PrismaExceptionFilter } from './common/filters/prisma-exception.filter';
import { buildValidationException } from './common/errors/validation.exception';
import type { SecurityConfig } from './config/security.config';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const configService = app.get(ConfigService);

  // Behind a proxy `request.ip` is the proxy's address unless Express is told
  // to trust X-Forwarded-For — without this the login rate limiter would see
  // every request as coming from one client.
  app.set('trust proxy', true);

  // Security headers (CSP, HSTS, no-sniff, frame protection). Swagger UI needs
  // inline styles, so its CSP directive is relaxed just enough to render.
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          'default-src': ["'self'"],
          'style-src': ["'self'", "'unsafe-inline'"],
          'img-src': ["'self'", 'data:'],
        },
      },
      crossOriginEmbedderPolicy: false,
    }),
  );

  // CORS protects the *browser user*, so the allow-list is explicit and comes
  // from configuration — never `*` alongside credentials.
  const security = configService.get<SecurityConfig>('security');
  app.enableCors({
    origin: security?.corsOrigins ?? [],
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-request-id'],
    exposedHeaders: ['x-request-id', 'Retry-After'],
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
      // Field-level failures, not one flattened string: clients can point at
      // the offending input instead of parsing prose.
      exceptionFactory: buildValidationException,
    }),
  );

  // Order matters: the narrow filter first, the catch-all last.
  app.useGlobalFilters(new PrismaExceptionFilter(), new HttpExceptionFilter());
  app.enableShutdownHooks();

  const config = new DocumentBuilder()
    .setTitle('CourseFlow Nest API')
    .setDescription('Runnable backend assembled from the CourseFlow course')
    .setVersion('1.0.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('docs', app, document);

  const port = configService.get<number>('PORT') ?? Number(process.env.PORT ?? 3000);
  await app.listen(port);
  Logger.log(
    `CourseFlow Nest API listening on http://localhost:${port} (docs at /docs)`,
    'Bootstrap',
  );
}

void bootstrap();
