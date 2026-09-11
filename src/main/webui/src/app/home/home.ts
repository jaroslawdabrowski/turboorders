import { HttpClient } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { MatCardModule } from '@angular/material/card';
import { TranslatePipe } from '@ngx-translate/core';

interface GreetingResponse {
  servedBy: string;
  servedAt: string;
}

@Component({
  selector: 'app-home',
  imports: [MatCardModule, TranslatePipe],
  templateUrl: './home.html',
  styleUrl: './home.scss',
})
export class Home {
  private readonly http = inject(HttpClient);

  readonly backendReachable = signal(false);

  constructor() {
    this.http.get<GreetingResponse>('/api/hello').subscribe({
      next: () => this.backendReachable.set(true),
      error: () => this.backendReachable.set(false),
    });
  }
}
