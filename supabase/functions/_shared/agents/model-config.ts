export const productionModel={
  id:'google/gemini-3.1-flash-lite',
  maxOutputTokens:3600,
  temperature:1,
  reasoning:'low',
} as const;

export const comparisonModels=[productionModel.id,'google/gemini-3.1-pro-preview'] as const;
export type ComparisonModel=typeof comparisonModels[number];
