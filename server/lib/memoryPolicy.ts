export const MAX_MEMORIES = 40;
export const MAX_MEMORY_CHARS = 500;

export const MAX_PROFILE_FIELD_CHARS = 200;
export const MAX_PROFILE_INSTRUCTION_CHARS = 1500;

export type UserProfile = {
  nickname?: string;
  occupation?: string;
  about?: string;
  instructions?: string;
  memoryEnabled?: boolean;
};
