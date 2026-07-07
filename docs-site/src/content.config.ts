import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({
		loader: docsLoader(),
		schema: docsSchema({
			extend: z.object({
				// Extra search phrases so casual queries ("merge pdfs", "cambiar idioma")
				// hit the right page — rendered as hidden, weighted text for Pagefind.
				keywords: z.array(z.string()).optional(),
				badge: z.enum(['pro', 'new']).optional(),
			}),
		}),
	}),
};
