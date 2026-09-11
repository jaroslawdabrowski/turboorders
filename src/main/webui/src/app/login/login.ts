import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { TranslatePipe } from '@ngx-translate/core';
import { AuthService } from '../core/auth.service';

@Component({
  selector: 'app-login',
  imports: [FormsModule, MatButtonModule, MatCardModule, MatFormFieldModule, MatInputModule, TranslatePipe],
  templateUrl: './login.html',
  styleUrl: './login.scss',
})
export class Login {
  private readonly authService = inject(AuthService);
  private readonly router = inject(Router);

  readonly username = signal('');
  readonly password = signal('');
  readonly errorKey = signal<string | null>(null);
  readonly submitting = signal(false);

  async submit(): Promise<void> {
    this.errorKey.set(null);
    this.submitting.set(true);
    try {
      await this.authService.login(this.username(), this.password());
      await this.router.navigateByUrl('/');
    } catch {
      this.errorKey.set('login.error');
    } finally {
      this.submitting.set(false);
    }
  }
}
