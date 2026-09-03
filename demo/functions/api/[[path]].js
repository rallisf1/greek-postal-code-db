import { handleApi } from '../_lib/api.js';

export async function onRequest(context) {
  return handleApi(context.request, context.env.DB);
}
