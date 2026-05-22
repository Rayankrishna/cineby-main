import app from './app';
import { env } from './env';

if (!process.env.VERCEL) {
  app.listen(env.PORT, () => {
    console.log(`Reelix API listening on http://localhost:${env.PORT}`);
  });
}

export default app;
