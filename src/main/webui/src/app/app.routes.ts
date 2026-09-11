import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';

export const routes: Routes = [
  { path: '', loadComponent: () => import('./home/home').then((m) => m.Home), canActivate: [authGuard] },
  { path: 'login', loadComponent: () => import('./login/login').then((m) => m.Login) },
];
