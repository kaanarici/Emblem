import { z } from "zod";

export const savedCategorySchema = z
  .enum([
    "hotels-vacation-rentals",
    "flights",
    "food-drinks",
    "recipes",
    "places",
    "travel",
    "books",
    "films-tv",
    "music",
    "products",
    "learning",
    "work",
    "health-fitness",
    "general",
  ])
  .describe(
    "Invisible Saves classification for this actual subject, not the surrounding request. Choose the specific domain; use general only when no domain fits.",
  );
