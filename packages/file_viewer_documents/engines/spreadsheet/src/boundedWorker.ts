// SPDX-License-Identifier: Apache-2.0
// A local module worker with an inactivity deadline; no main-thread fallback.
import { SPREADSHEET_LIMITS } from './limits.js';

export class BoundedSpreadsheetWorker extends EventTarget {
  private readonly worker: Worker;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private pending = 0;
  private closed = false;
  private readonly signal?: AbortSignal;

  constructor(create: () => Worker, signal?: AbortSignal, private readonly timeoutMs = SPREADSHEET_LIMITS.workerTimeoutMs) {
    super();
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > SPREADSHEET_LIMITS.workerTimeoutMs) {
      throw new Error('Invalid spreadsheet worker deadline.');
    }
    if (signal?.aborted) throw new DOMException('Spreadsheet parsing was aborted.', 'AbortError');
    this.signal = signal;
    this.worker = create();
    this.worker.addEventListener('message', this.onMessage);
    this.worker.addEventListener('error', this.onError);
    this.worker.addEventListener('messageerror', this.onMessageError);
    signal?.addEventListener('abort', this.onAbort, { once: true });
  }

  postMessage(message: unknown): void {
    if (this.closed) throw new Error('Spreadsheet parsing worker is closed.');
    this.pending++;
    this.arm();
    try {
      this.worker.postMessage(message);
    } catch (error) {
      this.terminate();
      throw error;
    }
  }

  terminate(): void {
    if (this.closed) return;
    this.closed = true;
    clearTimeout(this.timer);
    this.timer = undefined;
    this.signal?.removeEventListener('abort', this.onAbort);
    this.worker.removeEventListener('message', this.onMessage);
    this.worker.removeEventListener('error', this.onError);
    this.worker.removeEventListener('messageerror', this.onMessageError);
    this.worker.terminate();
  }

  private arm(): void {
    clearTimeout(this.timer);
    this.timer = this.pending > 0
      ? setTimeout(() => this.fail('Spreadsheet parsing exceeded the 30-second worker limit.'), this.timeoutMs)
      : undefined;
  }

  private fail(message: string): void {
    if (this.closed) return;
    this.terminate();
    const event = new Event('error');
    Object.defineProperty(event, 'message', { value: message });
    this.dispatchEvent(event);
  }

  private readonly onAbort = () => this.fail('Spreadsheet parsing was aborted.');
  private readonly onError = (event: Event) => this.fail((event as ErrorEvent).message || 'Spreadsheet worker failed.');
  private readonly onMessageError = () => this.fail('Spreadsheet worker returned an unreadable message.');
  private readonly onMessage = (event: MessageEvent) => {
    if (this.closed) return;
    if (!event.data || !['sheets', 'parseSheet', 'parseError', 'searchWorkbook'].includes(event.data.type)) {
      this.fail('Spreadsheet worker returned an unexpected message.');
      return;
    }
    this.pending = Math.max(0, this.pending - 1);
    this.arm();
    this.dispatchEvent(new MessageEvent('message', { data: event.data }));
    if (event.data.type === 'parseError') this.terminate();
  };
}
