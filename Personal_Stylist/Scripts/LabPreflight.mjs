import { verifiedProvider } from '../../evals/lab/providers.ts';
import { productionModel } from '../../supabase/functions/_shared/agents/model-config.ts';

try {
  const settings = { model: productionModel.id, route: 'google-vertex/global', maxOutputTokens: productionModel.maxOutputTokens, temperature: productionModel.temperature, reasoningEffort: productionModel.reasoning };
  const verified = await verifiedProvider(settings, true, AbortSignal.timeout(15000));
  const response = await fetch('https://openrouter.ai/api/v1/key', {
    signal: AbortSignal.timeout(10000),
    headers: { Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}` },
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error('OpenRouter did not accept the API key in supabase/functions/.env.');
  }
  const { data } = await response.json();
  if (!data || data.limit_remaining != null && data.limit_remaining <= 0) throw new Error('The OpenRouter key has no remaining allowance.');
  console.log(`OpenRouter key and ${settings.model} route verified. No inference calls made.`);
  console.log(`Conservative Flash reservation: $${(verified.bound / 1e6).toFixed(3)} per possible call; known actual cost is settled afterward.`);
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Live preflight failed.');
  process.exitCode = 1;
}
