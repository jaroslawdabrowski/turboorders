import { Component, OnInit, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatButtonModule } from '@angular/material/button';
import { MatMenuModule } from '@angular/material/menu';
import { LanguageService, SUPPORTED_LANGUAGES, type Language } from './core/language.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, MatToolbarModule, MatButtonModule, MatMenuModule],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  private readonly languageService = inject(LanguageService);

  readonly languages = SUPPORTED_LANGUAGES;

  ngOnInit(): void {
    this.languageService.init();
  }

  currentLanguage(): Language {
    return this.languageService.current();
  }

  changeLanguage(language: Language): void {
    this.languageService.change(language);
  }
}
