export async function register() {
  const { reportEnv } = await import("./lib/env");
  reportEnv();
}
