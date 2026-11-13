// SPDX-License-Identifier: Apache-2.0
// CrispCloud adapter: DOM elements from the topic iframe belong to another realm.
// A parent-window `instanceof Element` check rejects those legitimate links.
export const findChmTopicLink = (target: EventTarget | null): HTMLElement | null => {
  const element = target as Element | null;
  if (element?.nodeType !== 1 || typeof element.closest !== 'function') return null;
  return element.closest<HTMLElement>('a[data-chm-link-kind],area[data-chm-link-kind]');
};
