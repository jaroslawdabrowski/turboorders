import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

const STORAGE_KEY = 'turboorders.auth';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly authHeader = signal<string | null>(sessionStorage.getItem(STORAGE_KEY));

  readonly isAuthenticated = computed(() => this.authHeader() !== null);

  getAuthHeader(): string | null {
    return this.authHeader();
  }

  async login(username: string, password: string): Promise<void> {
    const candidate = `Basic ${btoa(`${username}:${password}`)}`;
    await firstValueFrom(this.http.get('/api/hello', { headers: { Authorization: candidate } }));
    sessionStorage.setItem(STORAGE_KEY, candidate);
    this.authHeader.set(candidate);
  }

  logout(): void {
    sessionStorage.removeItem(STORAGE_KEY);
    this.authHeader.set(null);
  }
}
