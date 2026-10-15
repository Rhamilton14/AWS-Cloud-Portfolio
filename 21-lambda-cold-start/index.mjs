// Node.js version of the same function, used only for the runtime comparison.
const initStart = performance.now();
const INIT_MS = Math.round((performance.now() - initStart) * 10) / 10;
let isCold = true;

export const handler = async (event, context) => {
  const cold = isCold;
  isCold = false;
  const result = {
    cold_start: cold,
    module_init_ms: INIT_MS,
    memory_mb: Number(context.memoryLimitInMB),
    init_type: process.env.AWS_LAMBDA_INITIALIZATION_TYPE,
  };
  console.log(JSON.stringify(result));
  return { statusCode: 200, body: JSON.stringify(result) };
};
