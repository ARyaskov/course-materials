import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  const passwordHash = await argon2.hash('super-secret-password', {
    type: argon2.argon2id,
    memoryCost: 19456,
    timeCost: 2,
    parallelism: 1,
  });

  const instructor = await prisma.user.upsert({
    where: { email: 'ada@example.com' },
    update: { passwordHash },
    create: {
      email: 'ada@example.com',
      displayName: 'Ada Lovelace',
      passwordHash,
      role: 'instructor',
    },
  });

  await prisma.user.upsert({
    where: { email: 'student@example.com' },
    update: { passwordHash },
    create: {
      email: 'student@example.com',
      displayName: 'Grace Hopper',
      passwordHash,
      role: 'student',
    },
  });

  // The first admin is seeded rather than exposed through a public endpoint:
  // roles are granted by an admin, so someone has to exist to start the chain.
  await prisma.user.upsert({
    where: { email: 'admin@example.com' },
    update: { passwordHash },
    create: {
      email: 'admin@example.com',
      displayName: 'Root Admin',
      passwordHash,
      role: 'admin',
    },
  });

  const course = await prisma.course.upsert({
    where: { ownerId_title: { ownerId: instructor.id, title: 'Intro to CourseFlow' } },
    update: {},
    create: {
      ownerId: instructor.id,
      title: 'Intro to CourseFlow',
      description: 'A free, published sample course to enroll into.',
      priceCents: 0,
      status: 'published',
      publishedAt: new Date(),
      lessons: {
        create: [
          { title: 'Welcome', content: 'What we will build.', position: 1 },
          { title: 'Setup', content: 'pnpm install and run.', position: 2 },
        ],
      },
    },
  });

  console.log(`Seeded instructor=${instructor.email}, course=${course.title}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => {
    void prisma.$disconnect();
  });
