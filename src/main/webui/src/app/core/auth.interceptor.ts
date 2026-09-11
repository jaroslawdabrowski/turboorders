import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from './auth.service';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith('/api')) {
    return next(req);
  }

  const authHeader = inject(AuthService).getAuthHeader();
  if (!authHeader) {
    return next(req);
  }

  return next(req.clone({ setHeaders: { Authorization: authHeader } }));
};
