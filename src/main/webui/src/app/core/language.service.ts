import { Injectable, inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';

const STORAGE_KEY = 'turboorders.language';
export const SUPPORTED_LANGUAGES = ['pl', 'en'] as const;
export type Language = (typeof SUPPORTED_LANGUAGES)[number];
export const DEFAULT_LANGUAGE: Language = 'pl';

@Injectable({ providedIn: 'root' })
export class LanguageService {
  private readonly translate = inject(TranslateService);

  init(): void {
    const stored = localStorage.getItem(STORAGE_KEY);
    const language = this.isSupported(stored) ? stored : DEFAULT_LANGUAGE;
    this.translate.use(language);
  }

  current(): Language {
    const currentLang = this.translate.currentLang();
    return this.isSupported(currentLang) ? currentLang : DEFAULT_LANGUAGE;
  }

  change(language: Language): void {
    this.translate.use(language);
    localStorage.setItem(STORAGE_KEY, language);
  }

  private isSupported(value: string | null): value is Language {
    return !!value && (SUPPORTED_LANGUAGES as readonly string[]).includes(value);
  }
}
