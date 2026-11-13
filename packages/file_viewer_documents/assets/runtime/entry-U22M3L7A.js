import {
  SPREADSHEET_LIMITS,
  assertSpreadsheetInput,
  extremaPointIndexes,
  tinycolor
} from "./chunk-X6YCA5GR.js";
import {
  createFileViewerWorkerController,
  resolveFileViewerColorScheme
} from "./chunk-3E27RFED.js";
import "./chunk-UIIGQOVD.js";
import "./chunk-V2DBS5C2.js";
import "./chunk-XPXVZBDO.js";
import {
  createEmptyFileViewerSearchState,
  createFileViewerZoomChangeEmitter,
  registerFileViewerSearchProvider,
  registerFileViewerViewStateProvider,
  registerFileViewerZoomProvider,
  resolveFileViewerFitScale,
  unregisterFileViewerSearchProvider,
  unregisterFileViewerViewStateProvider,
  unregisterFileViewerZoomProvider
} from "./chunk-B3J7LI27.js";
import {
  createFileViewerTranslator
} from "./chunk-X3L4DUK6.js";
import "./chunk-PIRHQTI4.js";

// packages/renderers/spreadsheet/src/boundedWorker.ts
var BoundedSpreadsheetWorker = class extends EventTarget {
  constructor(create, signal, timeoutMs = SPREADSHEET_LIMITS.workerTimeoutMs) {
    super();
    this.timeoutMs = timeoutMs;
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > SPREADSHEET_LIMITS.workerTimeoutMs) {
      throw new Error("Invalid spreadsheet worker deadline.");
    }
    if (signal?.aborted) throw new DOMException("Spreadsheet parsing was aborted.", "AbortError");
    this.signal = signal;
    this.worker = create();
    this.worker.addEventListener("message", this.onMessage);
    this.worker.addEventListener("error", this.onError);
    this.worker.addEventListener("messageerror", this.onMessageError);
    signal?.addEventListener("abort", this.onAbort, { once: true });
  }
  timeoutMs;
  worker;
  timer;
  pending = 0;
  closed = false;
  signal;
  postMessage(message) {
    if (this.closed) throw new Error("Spreadsheet parsing worker is closed.");
    this.pending++;
    this.arm();
    try {
      this.worker.postMessage(message);
    } catch (error) {
      this.terminate();
      throw error;
    }
  }
  terminate() {
    if (this.closed) return;
    this.closed = true;
    clearTimeout(this.timer);
    this.timer = void 0;
    this.signal?.removeEventListener("abort", this.onAbort);
    this.worker.removeEventListener("message", this.onMessage);
    this.worker.removeEventListener("error", this.onError);
    this.worker.removeEventListener("messageerror", this.onMessageError);
    this.worker.terminate();
  }
  arm() {
    clearTimeout(this.timer);
    this.timer = this.pending > 0 ? setTimeout(() => this.fail("Spreadsheet parsing exceeded the 30-second worker limit."), this.timeoutMs) : void 0;
  }
  fail(message) {
    if (this.closed) return;
    this.terminate();
    const event = new Event("error");
    Object.defineProperty(event, "message", { value: message });
    this.dispatchEvent(event);
  }
  onAbort = () => this.fail("Spreadsheet parsing was aborted.");
  onError = (event) => this.fail(event.message || "Spreadsheet worker failed.");
  onMessageError = () => this.fail("Spreadsheet worker returned an unreadable message.");
  onMessage = (event) => {
    if (this.closed) return;
    if (!event.data || !["sheets", "parseSheet", "parseError", "searchWorkbook"].includes(event.data.type)) {
      this.fail("Spreadsheet worker returned an unexpected message.");
      return;
    }
    this.pending = Math.max(0, this.pending - 1);
    this.arm();
    this.dispatchEvent(new MessageEvent("message", { data: event.data }));
    if (event.data.type === "parseError") this.terminate();
  };
};

// packages/renderers/spreadsheet/src/spreadsheet/rangeNavigation.ts
var validRange = (range) => ["sheetId", "startRow", "startCol", "endRow", "endCol"].every((key) => {
  const value = range[key];
  return Number.isSafeInteger(value) && value >= 0;
}) && range.startRow <= range.endRow && range.startCol <= range.endCol && range.endRow < 1048576 && range.endCol < 16384;
var cloneState = (state) => ({
  ...state,
  zoom: state.zoom ? { ...state.zoom } : void 0,
  scroll: state.scroll ? { ...state.scroll } : void 0,
  navigation: state.navigation ? { ...state.navigation } : void 0,
  extra: state.extra ? { ...state.extra } : void 0,
  spreadsheet: state.spreadsheet ? {
    ...state.spreadsheet,
    range: state.spreadsheet.range ? { ...state.spreadsheet.range } : void 0
  } : void 0
});
var createSpreadsheetRangeNavigation = (options) => {
  let stopped;
  let status = "idle";
  let highlighted;
  let pending;
  let suppressEventsUntil = 0;
  const listeners = /* @__PURE__ */ new Set();
  const snapshot = (result = status) => {
    const state = cloneState(options.getState?.() || {});
    return {
      ...state,
      renderer: "spreadsheet-openxml",
      scale: options.getScale(),
      spreadsheet: {
        ...state.spreadsheet,
        range: highlighted ? { ...highlighted } : void 0,
        status: result
      }
    };
  };
  const emit = (action, source = "viewer", notify = pending?.options.notify !== false && Date.now() >= suppressEventsUntil) => {
    if (!notify) return;
    for (const listener of listeners) {
      listener({ state: snapshot(), action, source, timestamp: Date.now() });
    }
  };
  const settle = (result) => {
    status = result;
    const request = pending;
    pending = void 0;
    if (request) {
      request.resolve(snapshot());
      emit(request.options.action || "restore", request.options.source || "api", request.options.notify !== false);
    }
  };
  const cancel = (result = "cancelled") => {
    if (stopped === "disposed") return;
    const hadHighlight = !!highlighted;
    const hadPending = !!pending;
    if (result !== "cancelled") stopped = result;
    highlighted = void 0;
    options.clearJump();
    settle(result);
    if (hadHighlight && !hadPending) emit("restore", "viewer");
    if (result === "disposed") listeners.clear();
  };
  void options.ready.catch(() => {
    if (!stopped) cancel("failed");
  });
  const provider = {
    getState: snapshot,
    fit: options.fit,
    subscribe(listener) {
      if (stopped !== "disposed") listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    applyState(input, applyOptions = {}) {
      if (stopped) return snapshot(stopped);
      if (applyOptions.notify === false) suppressEventsUntil = Date.now() + 180;
      const state = cloneState(input);
      const range = state.spreadsheet?.range;
      cancel();
      if (range && !validRange(range)) {
        status = "rejected";
        return snapshot();
      }
      const sheetId = range?.sheetId ?? state.spreadsheet?.sheetId;
      if (sheetId !== void 0 && (!Number.isSafeInteger(sheetId) || sheetId < 0)) {
        status = "rejected";
        return snapshot();
      }
      options.onNavigate?.();
      status = "pending";
      return new Promise((resolve) => {
        const request = { range, options: { ...applyOptions }, resolve };
        pending = request;
        const isCurrent = () => pending === request && !stopped;
        const failed = () => {
          if (isCurrent()) cancel("failed");
        };
        const jump = () => {
          if (!isCurrent()) return;
          try {
            if (range) options.jump(range);
            else settle("idle");
          } catch {
            failed();
          }
        };
        void options.ready.then(() => {
          if (!isCurrent()) return;
          if (sheetId !== void 0 && !options.isVisibleSheet(sheetId)) {
            settle("rejected");
            return;
          }
          try {
            const restored = options.restoreState?.(state, isCurrent);
            if (restored) void Promise.resolve(restored).then(jump, failed);
            else jump();
          } catch {
            failed();
          }
        }, failed);
      });
    }
  };
  return {
    provider,
    cancel,
    notify: emit,
    isPending: () => !!pending?.range,
    /** Called after the target virtual window loads, before drawing the highlight. */
    prepare(totalRows, totalCols) {
      const request = pending;
      if (!request?.range) return null;
      if (request.range.endRow >= totalRows || request.range.endCol >= totalCols) {
        highlighted = void 0;
        options.clearJump();
        settle("rejected");
        return null;
      }
      highlighted = { ...request.range };
      return () => {
        if (pending === request) settle("applied");
      };
    },
    contains(sheetId, row, col) {
      return !!highlighted && highlighted.sheetId === sheetId && row >= highlighted.startRow && row <= highlighted.endRow && col >= highlighted.startCol && col <= highlighted.endCol;
    }
  };
};

// packages/renderers/spreadsheet/src/spreadsheet/chartRenderer.ts
var SVG_NAMESPACE = "http://www.w3.org/2000/svg";
var DEFAULT_COLORS = ["#4472c4", "#ed7d31", "#70ad47", "#ffc000", "#5b9bd5", "#a5a5a5"];
var MAX_LEGEND_ITEMS = 8;
var MAX_LINE_POINTS_PER_PIXEL = 2;
var svgElement = (documentRef, name, attributes = {}) => {
  const element = documentRef.createElementNS(SVG_NAMESPACE, name);
  Object.entries(attributes).forEach(([key, value]) => element.setAttribute(key, `${value}`));
  return element;
};
var svgText = (documentRef, value, x, y, options = {}) => {
  const text = svgElement(documentRef, "text", {
    x,
    y,
    "text-anchor": options.anchor || "start",
    "font-family": "Aptos, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif",
    "font-size": options.size || 11,
    "font-weight": options.weight || "400",
    fill: options.fill || "#5f6368"
  });
  if (options.rotate) {
    text.setAttribute("transform", `rotate(${options.rotate} ${x} ${y})`);
  }
  text.textContent = value;
  return text;
};
var axisFontSize = (chart, size, fallback) => {
  const scale = Math.min(chart.width / 640, chart.height / 360);
  return size !== void 0 && Number.isFinite(size) && size > 0 && Number.isFinite(scale) && scale > 0 ? size / scale : fallback;
};
var seriesColor = (series, index) => {
  return series.color || DEFAULT_COLORS[index % DEFAULT_COLORS.length];
};
var seriesStrokeWidth = (series) => {
  return Math.min(8, Math.max(0.5, series.lineWidth || 2.5));
};
var seriesDashArray = (series) => {
  switch (series.lineDash) {
    case "dash":
    case "sysDash":
      return "8 4";
    case "dashDot":
    case "sysDashDot":
      return "8 4 2 4";
    case "dot":
    case "sysDot":
      return "2 3";
    case "lgDash":
      return "12 5";
    case "lgDashDot":
      return "12 5 2 5";
    case "lgDashDotDot":
      return "12 5 2 5 2 5";
    default:
      return void 0;
  }
};
var showsSeriesLine = (chart, series) => {
  if (series.lineVisible === false) {
    return false;
  }
  return chart.type !== "scatter" || chart.scatterStyle?.toLowerCase() !== "marker";
};
var showsSeriesMarker = (chart, series) => {
  if (series.marker) {
    return series.marker.symbol.toLowerCase() !== "none";
  }
  if (chart.type !== "scatter") {
    return false;
  }
  const scatterStyle = (chart.scatterStyle || "lineMarker").toLowerCase();
  return scatterStyle === "marker" || scatterStyle.endsWith("marker");
};
var categoryLabelIndexes = (count, plotWidth) => {
  const limit = Math.max(2, Math.floor(plotWidth / 28));
  if (count <= limit) {
    return Array.from({ length: count }, (_, index) => index);
  }
  return Array.from(
    new Set(
      Array.from({ length: limit }, (_, index) => Math.round(index * (count - 1) / (limit - 1)))
    )
  );
};
var drawSeriesMarker = (documentRef, svg, series, color, x, y) => {
  const symbol = series.marker?.symbol.toLowerCase() || "circle";
  const radius = Math.min(10, Math.max(1.5, (series.marker?.size || 5) * 4 / 6));
  const common = {
    class: "excel-chart-marker",
    "data-marker-symbol": symbol
  };
  switch (symbol) {
    case "square":
      svg.appendChild(
        svgElement(documentRef, "rect", {
          ...common,
          x: x - radius,
          y: y - radius,
          width: radius * 2,
          height: radius * 2,
          fill: color
        })
      );
      break;
    case "diamond":
      svg.appendChild(
        svgElement(documentRef, "polygon", {
          ...common,
          points: `${x},${y - radius} ${x + radius},${y} ${x},${y + radius} ${x - radius},${y}`,
          fill: color
        })
      );
      break;
    case "triangle":
      svg.appendChild(
        svgElement(documentRef, "polygon", {
          ...common,
          points: `${x},${y - radius} ${x + radius},${y + radius} ${x - radius},${y + radius}`,
          fill: color
        })
      );
      break;
    case "dash":
      svg.appendChild(
        svgElement(documentRef, "line", {
          ...common,
          x1: x - radius,
          y1: y,
          x2: x + radius,
          y2: y,
          stroke: color,
          "stroke-width": 2
        })
      );
      break;
    case "plus":
      svg.appendChild(
        svgElement(documentRef, "path", {
          ...common,
          d: `M${x - radius},${y} L${x + radius},${y} M${x},${y - radius} L${x},${y + radius}`,
          fill: "none",
          stroke: color,
          "stroke-width": 1.5
        })
      );
      break;
    case "x":
      svg.appendChild(
        svgElement(documentRef, "path", {
          ...common,
          d: `M${x - radius},${y - radius} L${x + radius},${y + radius} M${x + radius},${y - radius} L${x - radius},${y + radius}`,
          fill: "none",
          stroke: color,
          "stroke-width": 1.5
        })
      );
      break;
    case "dot":
    case "circle":
    case "auto":
    default:
      svg.appendChild(
        svgElement(documentRef, "circle", {
          ...common,
          cx: x,
          cy: y,
          r: symbol === "dot" ? Math.max(1, radius / 2) : radius,
          fill: color
        })
      );
      break;
  }
};
var categoryLabels = (chart) => {
  const labels = chart.series.reduce((longest, series) => series.categories.length > longest.length ? series.categories : longest, []);
  const valueCount = chart.series.reduce(
    (count, series) => Math.max(count, series.values.length),
    0
  );
  return labels.length ? labels : Array.from({ length: valueCount }, (_, index) => `${index + 1}`);
};
var valueDomain = (chart) => {
  let min = 0;
  let max = 0;
  chart.series.forEach((series) => {
    series.values.forEach((value) => {
      if (!Number.isFinite(value)) {
        return;
      }
      min = Math.min(min, value);
      max = Math.max(max, value);
    });
  });
  if (min === max) {
    return { min: 0, max: Math.max(1, max), span: Math.max(1, max) };
  }
  return { min, max, span: max - min };
};
var createPlot = (chart) => {
  const hasTitle = !!chart.title;
  const hasLegend = !!chart.legendPosition;
  const rightLegend = chart.legendPosition === "right";
  const top = hasTitle ? 48 : 24;
  const bottom = hasLegend && !rightLegend ? 302 : 326;
  const left = chart.valueAxisTitle ? 76 : 58;
  const right = rightLegend ? 492 : 612;
  return {
    left,
    top,
    width: right - left,
    height: bottom - top,
    bottom
  };
};
var drawValueGrid = (documentRef, svg, plot, domain, fontSize = 10) => {
  const tickCount = 5;
  for (let index = 0; index <= tickCount; index += 1) {
    const ratio = index / tickCount;
    const y = plot.bottom - ratio * plot.height;
    const value = domain.min + ratio * domain.span;
    svg.appendChild(
      svgElement(documentRef, "line", {
        x1: plot.left,
        y1: y,
        x2: plot.left + plot.width,
        y2: y,
        stroke: index === 0 ? "#9ca3af" : "#e5e7eb",
        "stroke-width": 1
      })
    );
    svg.appendChild(
      svgText(
        documentRef,
        Number.isInteger(value) ? `${value}` : value.toFixed(1),
        plot.left - 8,
        y + fontSize / 3,
        {
          anchor: "end",
          size: fontSize
        }
      )
    );
  }
};
var drawCategoryLabels = (documentRef, svg, chart, plot, pointAxis = false) => {
  const categories = categoryLabels(chart);
  if (!categories.length) {
    return;
  }
  const categorySeries = chart.series.find((series) => series.categories === categories);
  const sourcePointCount = Math.max(
    ...chart.series.map((series) => series.sourcePointCount || Math.max(series.values.length, series.categories.length)),
    categories.length
  );
  const step = plot.width / categories.length;
  const visible = categories.flatMap((label, i) => label ? [i] : []);
  categoryLabelIndexes(visible.length, plot.width).forEach((visibleIndex) => {
    const index = visible[visibleIndex];
    const category = categories[index];
    const maxLength = categories.length > 8 ? 8 : 14;
    const label = category.length > maxLength ? `${category.slice(0, maxLength - 1)}\u2026` : category;
    const sourceIndex = categorySeries?.sourcePointIndexes?.[index] ?? index;
    const x = pointAxis && categories.length > 1 ? plot.left + sourceIndex / Math.max(sourcePointCount - 1, 1) * plot.width : plot.left + (index + 0.5) * step;
    const labelElement = svgText(documentRef, label, x, plot.bottom + 17, {
      anchor: "middle",
      size: axisFontSize(chart, chart.categoryAxisFontSize, 10)
    });
    labelElement.classList.add("excel-chart-category-label");
    labelElement.dataset.categoryIndex = `${sourceIndex}`;
    svg.appendChild(labelElement);
  });
};
var drawColumnChart = (documentRef, svg, chart, plot) => {
  const domain = valueDomain(chart);
  const categories = categoryLabels(chart);
  const categoryCount = Math.max(
    categories.length,
    chart.series.reduce((count, series) => Math.max(count, series.values.length), 0),
    1
  );
  const groupWidth = plot.width / categoryCount;
  const seriesCount = Math.max(chart.series.length, 1);
  const slotWidth = groupWidth * 0.76 / seriesCount;
  const zeroY = plot.bottom - (0 - domain.min) / domain.span * plot.height;
  drawValueGrid(documentRef, svg, plot, domain, axisFontSize(chart, chart.valueAxisFontSize, 10));
  chart.series.forEach((series, seriesIndex) => {
    series.values.forEach((value, valueIndex) => {
      if (!Number.isFinite(value)) return;
      const valueY = plot.bottom - (value - domain.min) / domain.span * plot.height;
      const x = plot.left + valueIndex * groupWidth + groupWidth * 0.12 + seriesIndex * slotWidth;
      const y = Math.min(zeroY, valueY);
      const rect = svgElement(documentRef, "rect", {
        x,
        y,
        width: Math.max(1, slotWidth - 2),
        height: Math.max(1, Math.abs(zeroY - valueY)),
        fill: seriesColor(series, seriesIndex),
        rx: 1
      });
      const title = svgElement(documentRef, "title");
      title.textContent = `${series.name}: ${value}`;
      rect.appendChild(title);
      svg.appendChild(rect);
    });
  });
  drawCategoryLabels(documentRef, svg, chart, plot);
};
var drawHorizontalBarChart = (documentRef, svg, chart, plot) => {
  const domain = valueDomain(chart);
  const categories = categoryLabels(chart);
  const categoryCount = Math.max(
    categories.length,
    chart.series.reduce((count, series) => Math.max(count, series.values.length), 0),
    1
  );
  const groupHeight = plot.height / categoryCount;
  const seriesCount = Math.max(chart.series.length, 1);
  const slotHeight = groupHeight * 0.76 / seriesCount;
  const zeroX = plot.left + (0 - domain.min) / domain.span * plot.width;
  for (let index = 0; index <= 5; index += 1) {
    const ratio = index / 5;
    const x = plot.left + ratio * plot.width;
    svg.appendChild(
      svgElement(documentRef, "line", {
        x1: x,
        y1: plot.top,
        x2: x,
        y2: plot.bottom,
        stroke: "#e5e7eb",
        "stroke-width": 1
      })
    );
  }
  chart.series.forEach((series, seriesIndex) => {
    series.values.forEach((value, valueIndex) => {
      if (!Number.isFinite(value)) return;
      const valueX = plot.left + (value - domain.min) / domain.span * plot.width;
      const y = plot.top + valueIndex * groupHeight + groupHeight * 0.12 + seriesIndex * slotHeight;
      svg.appendChild(
        svgElement(documentRef, "rect", {
          x: Math.min(zeroX, valueX),
          y,
          width: Math.max(1, Math.abs(valueX - zeroX)),
          height: Math.max(1, slotHeight - 2),
          fill: seriesColor(series, seriesIndex),
          rx: 1
        })
      );
    });
  });
  categories.forEach((category, index) => {
    svg.appendChild(
      svgText(documentRef, category, plot.left - 8, plot.top + (index + 0.5) * groupHeight + 4, {
        anchor: "end",
        size: axisFontSize(chart, chart.categoryAxisFontSize, 10)
      })
    );
  });
};
var drawLineChart = (documentRef, svg, chart, plot, fillArea) => {
  const domain = valueDomain(chart);
  const count = Math.max(
    chart.series.reduce(
      (pointCount, series) => Math.max(pointCount, series.sourcePointCount || series.values.length),
      0
    ),
    1
  );
  const step = count > 1 ? plot.width / (count - 1) : plot.width;
  drawValueGrid(documentRef, svg, plot, domain, axisFontSize(chart, chart.valueAxisFontSize, 10));
  chart.series.forEach((series, seriesIndex) => {
    const pointIndexes = extremaPointIndexes(
      series.values,
      Math.max(64, Math.floor(plot.width * MAX_LINE_POINTS_PER_PIXEL)),
      series.spanBlankIndexes
    );
    const spanning = new Set(series.spanBlankIndexes || []);
    const segments = [];
    let segment = [];
    for (const index of pointIndexes) {
      const value = series.values[index];
      if (!Number.isFinite(value)) {
        if (spanning.has(index)) continue;
        if (segment.length) segments.push(segment);
        segment = [];
        continue;
      }
      const sourceIndex = series.sourcePointIndexes?.[index] ?? index;
      segment.push({
        x: plot.left + (count > 1 ? sourceIndex * step : plot.width / 2),
        y: plot.bottom - (value - domain.min) / domain.span * plot.height
      });
    }
    if (segment.length) segments.push(segment);
    const points = segments.flat();
    if (!points.length) return;
    const pathFor = (points2) => points2.map((point, index) => `${index ? "L" : "M"}${point.x},${point.y}`).join(" ");
    const pathData = segments.map(pathFor).join(" ");
    if (fillArea) {
      const zeroY = plot.bottom - (0 - domain.min) / domain.span * plot.height;
      for (const points2 of segments) {
        if (points2.length < 2) continue;
        svg.appendChild(svgElement(documentRef, "path", {
          class: "excel-chart-area",
          d: `${pathFor(points2)} L${points2[points2.length - 1].x},${zeroY} L${points2[0].x},${zeroY} Z`,
          fill: seriesColor(series, seriesIndex),
          opacity: 0.2
        }));
      }
    }
    const color = seriesColor(series, seriesIndex);
    const dashArray = seriesDashArray(series);
    if (showsSeriesLine(chart, series)) {
      svg.appendChild(
        svgElement(documentRef, "path", {
          class: "excel-chart-series-line",
          "data-source-point-count": series.sourcePointCount || series.values.length,
          "data-transferred-point-count": series.values.length,
          "data-rendered-point-count": points.length,
          d: pathData,
          fill: "none",
          stroke: color,
          "stroke-width": seriesStrokeWidth(series),
          ...dashArray ? { "stroke-dasharray": dashArray } : {},
          "stroke-linejoin": "round",
          "stroke-linecap": "round"
        })
      );
    }
    if (showsSeriesMarker(chart, series)) {
      points.forEach((point) => drawSeriesMarker(documentRef, svg, series, color, point.x, point.y));
    }
  });
  drawCategoryLabels(documentRef, svg, chart, plot, true);
};
var polarPoint = (cx, cy, radius, angle) => {
  const radians = (angle - 90) * Math.PI / 180;
  return {
    x: cx + radius * Math.cos(radians),
    y: cy + radius * Math.sin(radians)
  };
};
var pieSlicePath = (cx, cy, outerRadius, innerRadius, startAngle, endAngle) => {
  if (endAngle - startAngle >= 360 - 1e-7) {
    const a = polarPoint(cx, cy, outerRadius, startAngle);
    const b = polarPoint(cx, cy, outerRadius, startAngle + 180);
    const outer = `M${a.x},${a.y} A${outerRadius},${outerRadius} 0 1,0 ${b.x},${b.y} A${outerRadius},${outerRadius} 0 1,0 ${a.x},${a.y} Z`;
    if (!innerRadius) return outer;
    const c = polarPoint(cx, cy, innerRadius, startAngle);
    const d = polarPoint(cx, cy, innerRadius, startAngle + 180);
    return `${outer} M${c.x},${c.y} A${innerRadius},${innerRadius} 0 1,1 ${d.x},${d.y} A${innerRadius},${innerRadius} 0 1,1 ${c.x},${c.y} Z`;
  }
  const outerStart = polarPoint(cx, cy, outerRadius, endAngle);
  const outerEnd = polarPoint(cx, cy, outerRadius, startAngle);
  const largeArc = endAngle - startAngle > 180 ? 1 : 0;
  if (!innerRadius) {
    return `M${cx},${cy} L${outerStart.x},${outerStart.y} A${outerRadius},${outerRadius} 0 ${largeArc},0 ${outerEnd.x},${outerEnd.y} Z`;
  }
  const innerStart = polarPoint(cx, cy, innerRadius, startAngle);
  const innerEnd = polarPoint(cx, cy, innerRadius, endAngle);
  return `M${outerStart.x},${outerStart.y} A${outerRadius},${outerRadius} 0 ${largeArc},0 ${outerEnd.x},${outerEnd.y} L${innerStart.x},${innerStart.y} A${innerRadius},${innerRadius} 0 ${largeArc},1 ${innerEnd.x},${innerEnd.y} Z`;
};
var drawPieChart = (documentRef, svg, chart, doughnut) => {
  const series = chart.series[0];
  const values = series?.values || [];
  const categories = series?.categories || [];
  const max = values.reduce((m, v) => Number.isFinite(v) ? Math.max(m, v) : m, 0) || 1;
  const total = values.reduce((sum, value) => sum + (Number.isFinite(value) ? Math.max(0, value) / max : 0), 0) || 1;
  const cx = chart.legendPosition === "right" ? 260 : 320;
  const cy = chart.title ? 180 : 170;
  const radius = 120;
  let angle = 0;
  values.forEach((value, index) => {
    if (!Number.isFinite(value) || value <= 0) return;
    const nextAngle = angle + value / max / total * 360;
    const color = DEFAULT_COLORS[index % DEFAULT_COLORS.length];
    const path = svgElement(documentRef, "path", {
      d: pieSlicePath(cx, cy, radius, doughnut ? 62 : 0, angle, nextAngle),
      fill: color,
      stroke: "#ffffff",
      "stroke-width": 1.5
    });
    const title = svgElement(documentRef, "title");
    title.textContent = `${categories[index] || index + 1}: ${value}`;
    path.appendChild(title);
    svg.appendChild(path);
    angle = nextAngle;
  });
};
var drawLegend = (documentRef, svg, chart) => {
  if (!chart.legendPosition) {
    return;
  }
  const right = chart.legendPosition === "right";
  const categorySeries = chart.type === "pie" || chart.type === "doughnut" ? chart.series[0] : void 0;
  const entries = chart.type === "pie" || chart.type === "doughnut" ? (categorySeries?.values || []).slice(0, MAX_LEGEND_ITEMS).map((_, index) => ({
    ...categorySeries,
    name: categorySeries.categories[index] || `${index + 1}`,
    color: DEFAULT_COLORS[index % DEFAULT_COLORS.length]
  })) : chart.series;
  entries.slice(0, MAX_LEGEND_ITEMS).forEach((series, index) => {
    const x = right ? 510 : 76 + index % 4 * 136;
    const y = right ? 72 + index * 28 : 342 - Math.floor(index / 4) * 20;
    const color = seriesColor(series, index);
    const lineLike = chart.type === "line" || chart.type === "scatter" || chart.type === "radar";
    if (lineLike) {
      if (showsSeriesLine(chart, series)) {
        const dashArray = seriesDashArray(series);
        svg.appendChild(
          svgElement(documentRef, "line", {
            x1: x,
            y1: y - 5,
            x2: x + 12,
            y2: y - 5,
            stroke: color,
            "stroke-width": seriesStrokeWidth(series),
            ...dashArray ? { "stroke-dasharray": dashArray } : {}
          })
        );
      }
      if (showsSeriesMarker(chart, series)) {
        drawSeriesMarker(documentRef, svg, series, color, x + 6, y - 5);
      }
    } else {
      svg.appendChild(
        svgElement(documentRef, "rect", {
          x,
          y: y - 10,
          width: 10,
          height: 10,
          fill: color
        })
      );
    }
    const label = series.name.length > 16 ? `${series.name.slice(0, 15)}\u2026` : series.name;
    svg.appendChild(svgText(documentRef, label, x + 18, y, { size: 10 }));
  });
};
var renderSpreadsheetChart = (documentRef, chart) => {
  const container = documentRef.createElement("div");
  container.className = "excel-chart";
  container.dataset.chartId = chart.id;
  container.dataset.chartType = chart.type;
  container.dataset.seriesNames = JSON.stringify(chart.series.map((series) => series.name));
  container.dataset.seriesMarkers = JSON.stringify(
    chart.series.map((series) => series.marker?.symbol || null)
  );
  container.setAttribute("role", "img");
  container.setAttribute("aria-label", chart.title || chart.id || "Spreadsheet chart");
  const svg = svgElement(documentRef, "svg", {
    viewBox: "0 0 640 360",
    preserveAspectRatio: "xMidYMid meet",
    focusable: "false",
    "aria-hidden": "true"
  });
  svg.appendChild(
    svgElement(documentRef, "rect", {
      x: 0.5,
      y: 0.5,
      width: 639,
      height: 359,
      fill: "#ffffff",
      stroke: "#d1d5db"
    })
  );
  if (chart.title) {
    svg.appendChild(
      svgText(documentRef, chart.title, 320, 28, {
        anchor: "middle",
        size: 16,
        weight: "600",
        fill: "#1f2937"
      })
    );
  }
  const plot = createPlot(chart);
  switch (chart.type) {
    case "pie":
      drawPieChart(documentRef, svg, chart, false);
      break;
    case "doughnut":
      drawPieChart(documentRef, svg, chart, true);
      break;
    case "line":
    case "scatter":
    case "radar":
      drawLineChart(documentRef, svg, chart, plot, false);
      break;
    case "area":
      drawLineChart(documentRef, svg, chart, plot, true);
      break;
    case "bar":
    default:
      if (chart.barDirection === "bar") {
        drawHorizontalBarChart(documentRef, svg, chart, plot);
      } else {
        drawColumnChart(documentRef, svg, chart, plot);
      }
      break;
  }
  if (chart.categoryAxisTitle && chart.type !== "pie" && chart.type !== "doughnut") {
    svg.appendChild(
      svgText(documentRef, chart.categoryAxisTitle, plot.left + plot.width / 2, 324, {
        anchor: "middle",
        size: 11,
        fill: "#374151"
      })
    );
  }
  if (chart.valueAxisTitle && chart.type !== "pie" && chart.type !== "doughnut") {
    svg.appendChild(
      svgText(documentRef, chart.valueAxisTitle, 18, plot.top + plot.height / 2, {
        anchor: "middle",
        size: 11,
        fill: "#374151",
        rotate: -90
      })
    );
  }
  drawLegend(documentRef, svg, chart);
  container.appendChild(svg);
  return container;
};

// packages/renderers/spreadsheet/src/spreadsheet/imageSource.ts
var MAX_TIFF_SOURCE_BYTES = 32 * 1024 * 1024;
var MAX_TIFF_DIMENSION = 16384;
var MAX_TIFF_PIXELS = 24e6;
var getBase64Payload = (source) => {
  const match = /^data:([^;,]*);base64,([\s\S]*)$/i.exec(source);
  if (!match) {
    return void 0;
  }
  return { mime: match[1].toLowerCase(), payload: match[2] };
};
var decodeBase64Head = (payload, atob) => {
  try {
    return atob(payload.slice(0, 12));
  } catch {
    return "";
  }
};
var hasTiffHeader = (binary) => binary.length >= 4 && (binary.charCodeAt(0) === 73 && binary.charCodeAt(1) === 73 && binary.charCodeAt(2) === 42 && binary.charCodeAt(3) === 0 || binary.charCodeAt(0) === 77 && binary.charCodeAt(1) === 77 && binary.charCodeAt(2) === 0 && binary.charCodeAt(3) === 42);
var decodeBase64 = (payload, atob) => {
  const estimatedBytes = Math.floor(payload.length * 3 / 4);
  if (estimatedBytes > MAX_TIFF_SOURCE_BYTES) {
    throw new Error("TIFF source exceeds the embedded-image safety limit.");
  }
  const binary = atob(payload);
  if (binary.length > MAX_TIFF_SOURCE_BYTES) {
    throw new Error("TIFF source exceeds the embedded-image safety limit.");
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
};
var getTiffDimension = (ifd, tag, fallback) => {
  const tagged = ifd[tag];
  const value = Array.isArray(tagged) ? tagged[0] : tagged;
  const resolved = Number(value ?? ifd[fallback]);
  return Number.isFinite(resolved) ? resolved : 0;
};
var assertSafeTiffDimensions = (width, height) => {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 || width > MAX_TIFF_DIMENSION || height > MAX_TIFF_DIMENSION || width * height > MAX_TIFF_PIXELS) {
    throw new Error("TIFF dimensions exceed the embedded-image safety limit.");
  }
};
var loadUtif = async () => {
  const imported = await import("./UTIF-EAV2MPGD.js");
  return imported.default || imported;
};
var createSpreadsheetImageSourceResolver = (documentRef) => {
  const view = documentRef.defaultView;
  const decodeAtob = view?.atob.bind(view) || globalThis.atob.bind(globalThis);
  const urlApi = view?.URL || URL;
  const cache = /* @__PURE__ */ new Map();
  const objectUrls = /* @__PURE__ */ new Set();
  let disposed = false;
  const decodeTiff = async (source, payload) => {
    const bytes = decodeBase64(payload, decodeAtob);
    const input = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const utif = await loadUtif();
    const ifd = utif.decode(input)[0];
    if (!ifd) {
      throw new Error("TIFF image does not contain a decodable page.");
    }
    const encodedWidth = getTiffDimension(ifd, "t256", "width");
    const encodedHeight = getTiffDimension(ifd, "t257", "height");
    assertSafeTiffDimensions(encodedWidth, encodedHeight);
    utif.decodeImage(input, ifd);
    const width = getTiffDimension(ifd, "t256", "width");
    const height = getTiffDimension(ifd, "t257", "height");
    assertSafeTiffDimensions(width, height);
    const rgba = utif.toRGBA8(ifd);
    if (rgba.byteLength !== width * height * 4) {
      throw new Error("TIFF decoder returned an unexpected pixel buffer.");
    }
    const canvas = documentRef.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) {
      throw new Error("Canvas 2D is unavailable for TIFF conversion.");
    }
    const imageData = context.createImageData(width, height);
    imageData.data.set(rgba);
    context.putImageData(imageData, 0, 0);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
    if (!blob) {
      throw new Error("Unable to encode the TIFF preview as PNG.");
    }
    const objectUrl = urlApi.createObjectURL(blob);
    if (disposed) {
      urlApi.revokeObjectURL(objectUrl);
      return source;
    }
    objectUrls.add(objectUrl);
    return objectUrl;
  };
  return {
    resolve(image) {
      const parsed = getBase64Payload(image.src);
      if (!parsed) {
        return Promise.resolve(image.src);
      }
      const declaredTiff = /image\/(?:tif|tiff)/i.test(image.contentType || parsed.mime);
      const sniffedTiff = hasTiffHeader(decodeBase64Head(parsed.payload, decodeAtob));
      if (!declaredTiff && !sniffedTiff) {
        return Promise.resolve(image.src);
      }
      let pending = cache.get(image.src);
      if (!pending) {
        pending = decodeTiff(image.src, parsed.payload).catch(() => image.src);
        cache.set(image.src, pending);
      }
      return pending;
    },
    dispose() {
      disposed = true;
      objectUrls.forEach((url) => urlApi.revokeObjectURL(url));
      objectUrls.clear();
      cache.clear();
    }
  };
};

// packages/renderers/spreadsheet/src/spreadsheet/state.ts
var WINDOW_SIZE = 500;
var PREFETCH_AHEAD = 3;
var PREFETCH_BEHIND = 1;
var INDEX_COLUMN_KEY = "__index";
var ROW_KEY_FIELD = "__k";
var ROW_STATE_FIELD = "__s";
var DEFAULT_SHEET_DEFAULTS = {
  rowHeight: 20,
  colWidth: 64
};
var RowState = {
  Placeholder: 0,
  Loading: 1,
  Loaded: 2
};
var createEmptyVirtualState = () => ({
  active: false,
  totalRows: 0,
  totalCols: 0,
  indexOffset: 0,
  defaults: { ...DEFAULT_SHEET_DEFAULTS },
  dataKeys: [],
  rows: [],
  columns: [],
  cellCache: /* @__PURE__ */ new Map(),
  mergeStartMap: /* @__PURE__ */ new Map(),
  mergeCoveredMap: /* @__PURE__ */ new Map(),
  rowHeightCache: /* @__PURE__ */ new Map(),
  rowHeightOverrides: /* @__PURE__ */ new Map(),
  windowRows: /* @__PURE__ */ new Map(),
  windowCells: /* @__PURE__ */ new Map(),
  loadedWindows: /* @__PURE__ */ new Set(),
  loadingWindows: /* @__PURE__ */ new Set()
});
var displayCellKey = (row, col) => {
  return `${row}-${col}`;
};
var getDataKey = (index) => {
  return `c${index}`;
};
var getRowState = (row) => {
  return row?.[ROW_STATE_FIELD] ?? RowState.Placeholder;
};
var buildRows = (count) => {
  const rows = new Array(count);
  for (let index = 0; index < count; index += 1) {
    rows[index] = {
      [ROW_KEY_FIELD]: `${index}`,
      [ROW_STATE_FIELD]: RowState.Placeholder
    };
  }
  return rows;
};
var getMaxWindowStart = (totalRows) => {
  if (!totalRows) {
    return 0;
  }
  return Math.floor(Math.max(totalRows - 1, 0) / WINDOW_SIZE) * WINDOW_SIZE;
};
var clampWindowStart = (startRow = 0, totalRows = 0) => {
  return Math.min(Math.max(startRow, 0), getMaxWindowStart(totalRows));
};
var getWindowStart = (row = 0, totalRows = 0) => {
  const start = Math.floor(Math.max(row, 0) / WINDOW_SIZE) * WINDOW_SIZE;
  return clampWindowStart(start, totalRows);
};
var collectWindowStarts = ({
  startRow,
  endRow,
  direction,
  totalRows,
  far = false
}) => {
  const starts = /* @__PURE__ */ new Set();
  const firstWindow = getWindowStart(startRow, totalRows);
  const lastWindow = getWindowStart(endRow, totalRows);
  for (let current = firstWindow; current <= lastWindow; current += WINDOW_SIZE) {
    starts.add(current);
  }
  const ahead = far ? PREFETCH_AHEAD + 1 : PREFETCH_AHEAD;
  const behind = far ? PREFETCH_BEHIND + 1 : PREFETCH_BEHIND;
  const anchor = direction > 0 ? lastWindow : firstWindow;
  for (let step = 1; step <= ahead; step += 1) {
    starts.add(clampWindowStart(anchor + direction * step * WINDOW_SIZE, totalRows));
  }
  for (let step = 1; step <= behind; step += 1) {
    starts.add(clampWindowStart(anchor - direction * step * WINDOW_SIZE, totalRows));
  }
  return Array.from(starts);
};
var markWindowState = (rows, totalRows, windowStart, nextState) => {
  const endRow = Math.min(windowStart + WINDOW_SIZE, totalRows);
  for (let rowIndex = windowStart; rowIndex < endRow; rowIndex += 1) {
    const row = rows[rowIndex];
    if (!row) {
      continue;
    }
    row[ROW_STATE_FIELD] = nextState;
  }
};

// packages/renderers/spreadsheet/src/spreadsheet/view.ts
var INDEX_COLUMN_WIDTH = 68;
var SPREADSHEET_MIN_ZOOM = 0.25;
var SPREADSHEET_MAX_ZOOM = 2.5;
var TABLE_FONT_FAMILY = 'Aptos, Calibri, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif';
var TABLE_FONT_SIZE = 11;
var MIN_RENDERABLE_ROW_HEIGHT = 8;
var HIDDEN_ROW_HEIGHT = 0.1;
var CELL_PADDING = 2;
var CELL_LINE_HEIGHT = 1.2;
var HEADER_HEIGHT = 34;
var RESIZABLE_COLUMN_MIN_WIDTH = 40;
var RESIZABLE_ROW_MIN_HEIGHT = 18;
var EXCEL_HEADER_BG = "#f3f3f3";
var EXCEL_HEADER_TEXT = "#5f6368";
var EXCEL_GRID = "#d7dbe0";
var EXCEL_DARK_HEADER_BG = "#1f2937";
var EXCEL_DARK_HEADER_TEXT = "#cbd5e1";
var EXCEL_DARK_GRID = "#374151";
var EXCEL_DARK_BODY_BG = "#111827";
var EXCEL_DARK_BODY_TEXT = "#e5e7eb";
var EXCEL_GREEN = "#21a366";
var EXCEL_GREEN_SOFT = "rgba(33, 163, 102, 0.1)";
var DATA_AREA_MIN_COL_INDEX = 1;
var DEFAULT_BORDER_COLOR = "#000000";
var BORDER_STYLE_PRIORITY = {
  double: 8,
  solid: 7,
  dashed: 5,
  dotted: 4
};
var HEADER_FONT = `bold 12px ${TABLE_FONT_FAMILY}`;
var BODY_FONT = `${TABLE_FONT_SIZE}px ${TABLE_FONT_FAMILY}`;
var MAX_OVERFLOW_SCAN_COLS = 32;
var measureCanvas;
var textWidthCache = /* @__PURE__ */ new Map();
var normalizeZoomScale = (scale = 1) => {
  return Number.isFinite(scale) ? Math.min(SPREADSHEET_MAX_ZOOM, Math.max(SPREADSHEET_MIN_ZOOM, scale)) : 1;
};
var scaleNumber = (value, zoomScale) => {
  return Math.max(1, Math.round(value * normalizeZoomScale(zoomScale)));
};
var scaleFont = (font, zoomScale) => {
  if (!font) {
    return font;
  }
  const normalizedScale = normalizeZoomScale(zoomScale);
  return font.replace(/(\d+(?:\.\d+)?)px/g, (_, size) => {
    return `${Number(size) * normalizedScale}px`;
  });
};
var scaleBorder = (border, zoomScale) => {
  if (!border) {
    return void 0;
  }
  return {
    ...border,
    width: Math.max(0.5, border.width * normalizeZoomScale(zoomScale))
  };
};
var scaleRichText = (runs, zoomScale) => {
  if (!runs?.length) {
    return void 0;
  }
  const normalizedScale = normalizeZoomScale(zoomScale);
  return runs.map((run) => ({
    ...run,
    ...run.fontSize ? { fontSize: run.fontSize * normalizedScale } : {}
  }));
};
var scaleCellStyle = (style, zoomScale) => {
  if (!style) {
    return void 0;
  }
  return {
    ...style,
    font: scaleFont(style.font, zoomScale),
    richText: scaleRichText(style.richText, zoomScale),
    borderTop: scaleBorder(style.borderTop, zoomScale),
    borderRight: scaleBorder(style.borderRight, zoomScale),
    borderBottom: scaleBorder(style.borderBottom, zoomScale),
    borderLeft: scaleBorder(style.borderLeft, zoomScale)
  };
};
var getHeaderFont = (zoomScale) => scaleFont(HEADER_FONT, zoomScale) || HEADER_FONT;
var getBodyFont = (zoomScale) => scaleFont(BODY_FONT, zoomScale) || BODY_FONT;
var getIndexCellStyle = (zoomScale, darkMode = false) => ({
  backgroundColor: darkMode ? EXCEL_DARK_HEADER_BG : EXCEL_HEADER_BG,
  color: darkMode ? EXCEL_DARK_HEADER_TEXT : EXCEL_HEADER_TEXT,
  font: getHeaderFont(zoomScale)
});
var getLoadingCellStyle = (zoomScale, darkMode = false) => ({
  backgroundColor: darkMode ? "#18212f" : "#f4f7f9",
  color: darkMode ? "#94a3b8" : "#73808d",
  font: scaleFont(`italic ${TABLE_FONT_SIZE}px ${TABLE_FONT_FAMILY}`, zoomScale)
});
var cloneColumns = (columns) => {
  return columns.map((column) => ({
    ...column,
    ...column.children?.length ? { children: cloneColumns(column.children) } : {}
  }));
};
var CSS_GENERIC_FONT_FAMILIES = /* @__PURE__ */ new Set([
  "caption",
  "cursive",
  "emoji",
  "fangsong",
  "fantasy",
  "icon",
  "math",
  "menu",
  "message-box",
  "monospace",
  "sans-serif",
  "serif",
  "small-caption",
  "status-bar",
  "system-ui",
  "ui-monospace",
  "ui-rounded",
  "ui-sans-serif",
  "ui-serif"
]);
var normalizeFontFamily = (value) => {
  const family = typeof value === "string" ? value.trim() : "";
  if (!family) {
    return TABLE_FONT_FAMILY;
  }
  if (family.includes(",") || CSS_GENERIC_FONT_FAMILIES.has(family.toLowerCase())) {
    return family;
  }
  if (family.startsWith('"') && family.endsWith('"') || family.startsWith("'") && family.endsWith("'")) {
    return family;
  }
  return `"${family.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
};
var buildFont = (style) => {
  if (typeof style.font === "string" && style.font.trim()) {
    return style.font;
  }
  const hasFont = style.fontFamily !== void 0 || style.fontSize !== void 0 || style.fontWeight !== void 0 || style.fontStyle !== void 0;
  if (!hasFont) {
    return void 0;
  }
  const normalizedWeight = (() => {
    const { fontWeight } = style;
    if (typeof fontWeight === "number") {
      return fontWeight >= 600 ? "bold" : "normal";
    }
    if (typeof fontWeight === "string") {
      const trimmed = fontWeight.trim();
      if (/^\d+$/.test(trimmed)) {
        return Number(trimmed) >= 600 ? "bold" : "normal";
      }
      return trimmed;
    }
    return "normal";
  })();
  return [
    style.fontStyle || "normal",
    normalizedWeight,
    `${Number.parseFloat(style.fontSize) || TABLE_FONT_SIZE}px`,
    normalizeFontFamily(style.fontFamily)
  ].join(" ");
};
var alignFromClassName = (className) => {
  if (!className) {
    return void 0;
  }
  if (className.includes("htLeft")) {
    return "left";
  }
  if (className.includes("htRight")) {
    return "right";
  }
  if (className.includes("htCenter")) {
    return "center";
  }
  return void 0;
};
var verticalAlignFromClassName = (className) => {
  if (!className) {
    return void 0;
  }
  if (className.includes("htTop")) {
    return "top";
  }
  if (className.includes("htBottom")) {
    return "bottom";
  }
  if (className.includes("htMiddle")) {
    return "middle";
  }
  return void 0;
};
var hasClassName = (className, value) => {
  return !!className?.split(/\s+/).includes(value);
};
var getColumnWidth = (widths, index, fallback) => {
  if (typeof widths === "number") {
    return widths;
  }
  return widths?.[index] ?? fallback;
};
var getRenderColumnWidth = (column) => {
  const width = Number(column?.width);
  return Number.isFinite(width) && width > 0 ? width : 0;
};
var isVisibleDataColumn = (column) => {
  return !!column && !column.hide && getRenderColumnWidth(column) > 0;
};
var getSheetColumnsMeta = (ws) => {
  return ws.structure?.columns?.length ? ws.structure.columns : ws.columns;
};
var getSheetColWidths = (ws) => {
  return ws.structure?.colWidths ?? ws.colWidths;
};
var getRowHeight = (heights, index, fallback) => {
  if (typeof heights === "number") {
    return heights;
  }
  return heights?.[index] ?? fallback;
};
var normalizeRowHeight = (height, fallback) => {
  if (typeof height === "number" && Number.isFinite(height)) {
    if (height <= 0) {
      return HIDDEN_ROW_HEIGHT;
    }
    return Math.max(Math.ceil(height), MIN_RENDERABLE_ROW_HEIGHT);
  }
  return Math.max(Math.ceil(fallback), MIN_RENDERABLE_ROW_HEIGHT);
};
var isPlainTextCell = (value) => {
  if (value === null || value === void 0) {
    return false;
  }
  const text = `${value}`.trim();
  if (!text) {
    return false;
  }
  return !/^\d+([./:-]\d+)*$/.test(text);
};
var detectIndexOffset = (ws) => {
  const meta = ws.meta;
  const rows = ws.data || [];
  if (!meta || rows.length < 2 || (ws.merge || []).length) {
    return 0;
  }
  const firstRow = rows[0] || [];
  const secondRow = rows[1] || [];
  const firstRowValues = firstRow.filter((value) => `${value ?? ""}`.trim() !== "");
  const secondRowValues = secondRow.filter((value) => `${value ?? ""}`.trim() !== "");
  if (firstRowValues.length < Math.min(Math.max(Math.floor(meta.totalCols / 2), 3), 6)) {
    return 0;
  }
  if (!firstRowValues.every(isPlainTextCell) || secondRowValues.length < 2) {
    return 0;
  }
  return 1;
};
var buildColumns = (ws) => {
  const columnsMeta = getSheetColumnsMeta(ws);
  const colWidths = getSheetColWidths(ws);
  const columns = [{
    key: INDEX_COLUMN_KEY,
    title: "",
    type: "index",
    fixed: "left",
    width: INDEX_COLUMN_WIDTH,
    minWidth: INDEX_COLUMN_WIDTH,
    maxWidth: INDEX_COLUMN_WIDTH,
    widthFillDisable: true,
    headerAlign: "center",
    align: "center",
    headerVerticalAlign: "middle",
    verticalAlign: "middle",
    overflowTooltipShow: false,
    overflowTooltipHeaderShow: false
  }];
  const dataKeys = [];
  for (let index = 0; index < (ws.meta?.totalCols || 0); index += 1) {
    const key = getDataKey(index);
    const column = columnsMeta?.[index];
    const width = getColumnWidth(colWidths, index, ws.defaults.colWidth);
    const hidden = !!column?.hidden || width <= 0;
    const columnVerticalAlign = verticalAlignFromClassName(column?.className) || "middle";
    dataKeys.push(key);
    columns.push({
      key,
      title: column?.title || `${index + 1}`,
      width: hidden ? 0 : Math.max(Math.ceil(width), 1),
      hide: hidden,
      widthFillDisable: true,
      renderType: "both",
      headerAlign: "center",
      headerVerticalAlign: "middle",
      align: alignFromClassName(column?.className) || "left",
      verticalAlign: columnVerticalAlign,
      overflowTooltipShow: true,
      overflowTooltipHeaderShow: true
    });
  }
  return { columns, dataKeys };
};
var scaleColumn = (column, zoomScale) => {
  const nextColumn = {
    ...column,
    ...column.children?.length ? { children: column.children.map((child) => scaleColumn(child, zoomScale)) } : {}
  };
  const width = Number(column.width);
  if (Number.isFinite(width) && width > 0) {
    ;
    nextColumn.width = scaleNumber(width, zoomScale);
  }
  const minWidth = Number(column.minWidth);
  if (Number.isFinite(minWidth) && minWidth > 0) {
    ;
    nextColumn.minWidth = scaleNumber(minWidth, zoomScale);
  }
  const maxWidth = Number(column.maxWidth);
  if (Number.isFinite(maxWidth) && maxWidth > 0) {
    ;
    nextColumn.maxWidth = scaleNumber(maxWidth, zoomScale);
  }
  return nextColumn;
};
var getDisplayColumns = (columns, zoomScale = 1) => {
  const normalizedScale = normalizeZoomScale(zoomScale);
  if (normalizedScale === 1) {
    return cloneColumns(columns);
  }
  return columns.map((column) => scaleColumn(column, normalizedScale));
};
var getSearchColumnLeft = (columns, key) => {
  let left = 0;
  const visit = (list) => {
    for (const column of list) {
      if (column.hide) continue;
      if (column.children?.length) {
        const childLeft = visit(column.children);
        if (childLeft !== void 0) return childLeft;
      } else {
        if (`${column.key}` === key) return left;
        left += Number(column.width) || 0;
      }
    }
    return void 0;
  };
  return visit(columns);
};
var toBorderWidth = (value) => {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(value, 0);
  }
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? Math.max(parsed, 0) : 0;
  }
  return 0;
};
var toBorderStyle = (value) => {
  if (typeof value !== "string") {
    return "solid";
  }
  const style = value.trim();
  switch (style) {
    case "double":
    case "dashed":
    case "dotted":
    case "solid":
      return style;
    default:
      return "solid";
  }
};
var getBorderSide = (style, side) => {
  const width = toBorderWidth(style[`border${side}Width`]);
  if (!width) {
    return void 0;
  }
  return {
    width,
    style: toBorderStyle(style[`border${side}Style`]),
    color: style[`border${side}Color`] || DEFAULT_BORDER_COLOR
  };
};
var hasBorder = (style) => {
  if (!style) {
    return false;
  }
  return !!(style.borderTop || style.borderRight || style.borderBottom || style.borderLeft);
};
var hasTextLayout = (style) => {
  if (!style) {
    return false;
  }
  return !!(style.horizontalAlign || style.verticalAlign || style.wrapText || style.shrinkToFit);
};
var shouldRenderTextInOverlay = (style, column) => {
  if (style?.richText?.length) {
    return true;
  }
  if (!hasTextLayout(style)) {
    return false;
  }
  return !!(style?.wrapText || style?.shrinkToFit || style?.horizontalAlign && style.horizontalAlign !== (column?.align || "left") || style?.verticalAlign && style.verticalAlign !== (column?.verticalAlign || "middle"));
};
var toFlexJustify = (align) => {
  switch (align) {
    case "center":
      return "center";
    case "right":
      return "flex-end";
    default:
      return "flex-start";
  }
};
var toFlexAlign = (verticalAlign) => {
  switch (verticalAlign) {
    case "top":
      return "flex-start";
    case "bottom":
      return "flex-end";
    default:
      return "center";
  }
};
var toTextLayerLeft = (align, ownWidth, overflowWidth, leftRoom) => {
  switch (align) {
    case "right":
      return ownWidth - overflowWidth;
    case "center":
      return -Math.min(leftRoom, Math.max((overflowWidth - ownWidth) / 2, 0));
    default:
      return 0;
  }
};
var isHiddenVirtualRow = (row) => {
  return typeof row._height === "number" && row._height <= HIDDEN_ROW_HEIGHT;
};
var getDataColumnIndex = (column, fallbackColIndex) => {
  const key = column?.key;
  if (typeof key === "string" && key.startsWith("c")) {
    const index = Number(key.slice(1));
    if (Number.isInteger(index) && index >= 0) {
      return index;
    }
  }
  return Math.max(fallbackColIndex - 1, 0);
};
var getCellCacheKey = (rowIndex, colIndex, column) => {
  return displayCellKey(rowIndex, getDataColumnIndex(column, colIndex) + 1);
};
var getCellKeyByDataColumn = (rowIndex, dataColIndex) => {
  return displayCellKey(rowIndex, dataColIndex + 1);
};
var getTextValue = (value) => {
  if (value === null || value === void 0) {
    return "";
  }
  return `${value}`;
};
var hasRenderableValue = (value) => {
  return getTextValue(value).trim() !== "";
};
var isNumericLikeValue = (text) => {
  return /^[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?%?$/.test(text.trim());
};
var measureTextWidth = (text, font, padding, documentRef) => {
  const cacheKey = `${font}
${padding}
${text}`;
  const cached = textWidthCache.get(cacheKey);
  if (cached !== void 0) {
    return cached;
  }
  if (!measureCanvas && documentRef) {
    measureCanvas = documentRef.createElement("canvas");
  }
  const context = measureCanvas?.getContext("2d");
  if (!context) {
    return text.length * TABLE_FONT_SIZE;
  }
  context.font = font;
  const width = context.measureText(text).width + padding * 2;
  textWidthCache.set(cacheKey, width);
  return width;
};
var isBlankOverflowTarget = (virtualState, row, rowIndex, dataColIndex) => {
  const column = virtualState.columns[dataColIndex + 1];
  if (!isVisibleDataColumn(column)) {
    return false;
  }
  const cellKey = getCellKeyByDataColumn(rowIndex, dataColIndex);
  if (virtualState.mergeStartMap.has(cellKey) || virtualState.mergeCoveredMap.has(cellKey)) {
    return false;
  }
  return !hasRenderableValue(row[getDataKey(dataColIndex)]);
};
var collectOverflowRoom = (virtualState, row, rowIndex, dataColIndex, direction) => {
  let room = 0;
  for (let step = 1; step <= MAX_OVERFLOW_SCAN_COLS; step += 1) {
    const nextColIndex = dataColIndex + step * direction;
    if (nextColIndex < 0 || nextColIndex >= virtualState.totalCols) {
      break;
    }
    if (!isBlankOverflowTarget(virtualState, row, rowIndex, nextColIndex)) {
      break;
    }
    room += getRenderColumnWidth(virtualState.columns[nextColIndex + 1]);
  }
  return room;
};
var getExcelOverflowLayout = (virtualState, row, rowIndex, dataColIndex, column, style, value, zoomScale, documentRef) => {
  const text = getTextValue(value);
  if (!text || style?.wrapText || style?.shrinkToFit || isNumericLikeValue(text)) {
    return void 0;
  }
  const cellKey = getCellKeyByDataColumn(rowIndex, dataColIndex);
  if (virtualState.mergeStartMap.has(cellKey) || virtualState.mergeCoveredMap.has(cellKey)) {
    return void 0;
  }
  const ownWidth = getRenderColumnWidth(column);
  if (!ownWidth) {
    return void 0;
  }
  const font = style?.font || getBodyFont(zoomScale);
  const measuredWidth = Math.ceil(measureTextWidth(text, font, scaleNumber(CELL_PADDING, zoomScale), documentRef));
  if (measuredWidth <= ownWidth) {
    return void 0;
  }
  const align = style?.horizontalAlign || column?.align || "left";
  const leftRoom = align === "right" || align === "center" ? collectOverflowRoom(virtualState, row, rowIndex, dataColIndex, -1) : 0;
  const rightRoom = align !== "right" ? collectOverflowRoom(virtualState, row, rowIndex, dataColIndex, 1) : 0;
  const maxWidth = ownWidth + leftRoom + rightRoom;
  if (maxWidth <= ownWidth) {
    return void 0;
  }
  const width = Math.min(measuredWidth, maxWidth);
  return {
    left: toTextLayerLeft(align, ownWidth, width, leftRoom),
    width
  };
};
var getDataColumnSpanWidth = (virtualState, startDataColIndex, endDataColIndex) => {
  let width = 0;
  for (let index = startDataColIndex; index < endDataColIndex; index += 1) {
    width += getRenderColumnWidth(virtualState.columns[index + 1]);
  }
  return width;
};
var getLeftOverflowMirror = (virtualState, row, rowIndex, targetDataColIndex, zoomScale, documentRef) => {
  if (!isBlankOverflowTarget(virtualState, row, rowIndex, targetDataColIndex)) {
    return void 0;
  }
  const targetColumn = virtualState.columns[targetDataColIndex + 1];
  const targetWidth = getRenderColumnWidth(targetColumn);
  if (!targetWidth) {
    return void 0;
  }
  for (let step = 1; step <= MAX_OVERFLOW_SCAN_COLS; step += 1) {
    const sourceDataColIndex = targetDataColIndex - step;
    if (sourceDataColIndex < 0) {
      break;
    }
    const sourceColumn = virtualState.columns[sourceDataColIndex + 1];
    if (!isVisibleDataColumn(sourceColumn)) {
      break;
    }
    const sourceValue = row[getDataKey(sourceDataColIndex)];
    if (!hasRenderableValue(sourceValue)) {
      if (!isBlankOverflowTarget(virtualState, row, rowIndex, sourceDataColIndex)) {
        break;
      }
      continue;
    }
    const sourceCellKey = getCellKeyByDataColumn(rowIndex, sourceDataColIndex);
    const rawSourceStyle = virtualState.cellCache.get(sourceCellKey);
    const sourceStyle = {
      ...scaleCellStyle(rawSourceStyle, zoomScale) || {},
      horizontalAlign: rawSourceStyle?.horizontalAlign || sourceColumn?.align,
      verticalAlign: rawSourceStyle?.verticalAlign || sourceColumn?.verticalAlign
    };
    const sourceLayout = getExcelOverflowLayout(
      virtualState,
      row,
      rowIndex,
      sourceDataColIndex,
      sourceColumn,
      sourceStyle,
      sourceValue,
      zoomScale,
      documentRef
    );
    if (!sourceLayout) {
      return void 0;
    }
    const targetOffset = getDataColumnSpanWidth(
      virtualState,
      sourceDataColIndex,
      targetDataColIndex
    );
    const sourceTextLeft = sourceLayout.left;
    const sourceTextRight = sourceLayout.left + sourceLayout.width;
    const targetLeft = targetOffset;
    const targetRight = targetOffset + targetWidth;
    if (sourceTextLeft < targetRight && sourceTextRight > targetLeft) {
      return {
        value: sourceValue,
        style: sourceStyle,
        overflowLayout: {
          left: sourceLayout.left - targetOffset,
          width: sourceLayout.width
        }
      };
    }
    return void 0;
  }
  return void 0;
};
var getBorderScore = (border) => {
  if (!border) {
    return 0;
  }
  return border.width * 100 + (BORDER_STYLE_PRIORITY[border.style] || 1);
};
var getCollapsedBorderStyle = (virtualState, rowIndex, dataColIndex, style, zoomScale) => {
  const previousRow = scaleCellStyle(virtualState.cellCache.get(displayCellKey(rowIndex - 1, dataColIndex + 1)), zoomScale);
  const nextRow = scaleCellStyle(virtualState.cellCache.get(displayCellKey(rowIndex + 1, dataColIndex + 1)), zoomScale);
  const previousCol = scaleCellStyle(virtualState.cellCache.get(displayCellKey(rowIndex, dataColIndex)), zoomScale);
  const nextCol = scaleCellStyle(virtualState.cellCache.get(displayCellKey(rowIndex, dataColIndex + 2)), zoomScale);
  const borderTop = getBorderScore(style.borderTop) >= getBorderScore(previousRow?.borderBottom) ? style.borderTop : void 0;
  const borderBottom = getBorderScore(style.borderBottom) > getBorderScore(nextRow?.borderTop) ? style.borderBottom : void 0;
  const borderLeft = getBorderScore(style.borderLeft) >= getBorderScore(previousCol?.borderRight) ? style.borderLeft : void 0;
  const borderRight = getBorderScore(style.borderRight) > getBorderScore(nextCol?.borderLeft) ? style.borderRight : void 0;
  return {
    ...style,
    borderTop,
    borderRight,
    borderBottom,
    borderLeft
  };
};
var createBorderLine = (documentRef, side, border) => {
  const line = documentRef.createElement("span");
  const half = border.width / 2;
  Object.assign(line.style, {
    position: "absolute",
    pointerEvents: "none",
    boxSizing: "border-box"
  });
  if (side === "top" || side === "bottom") {
    Object.assign(line.style, {
      left: `${-half}px`,
      width: `calc(100% + ${border.width}px)`,
      height: "0"
    });
    line.style[side] = `${-half}px`;
    line.style.borderTop = `${border.width}px ${border.style} ${border.color}`;
  } else {
    Object.assign(line.style, {
      top: `${-half}px`,
      height: `calc(100% + ${border.width}px)`,
      width: "0"
    });
    line.style[side] = `${-half}px`;
    line.style.borderLeft = `${border.width}px ${border.style} ${border.color}`;
  }
  return line;
};
var createTextLayer = (documentRef, value, style, padding) => {
  const text = documentRef.createElement("span");
  Object.assign(text.style, {
    position: "relative",
    zIndex: "1",
    width: "100%",
    height: "100%",
    boxSizing: "border-box",
    display: "flex",
    alignItems: toFlexAlign(style.verticalAlign),
    justifyContent: toFlexJustify(style.horizontalAlign),
    padding: `0 ${padding}px`,
    overflow: "hidden",
    textOverflow: style.wrapText ? "clip" : "ellipsis",
    whiteSpace: style.wrapText ? "pre-wrap" : "nowrap",
    wordBreak: style.wrapText ? "break-word" : "normal",
    lineHeight: `${CELL_LINE_HEIGHT}`,
    textAlign: style.horizontalAlign || "left",
    color: style.color || "inherit",
    font: style.font || BODY_FONT,
    transform: style.shrinkToFit ? "scale(0.92)" : "none",
    transformOrigin: `${style.horizontalAlign || "left"} center`
  });
  if (style.richText?.length) {
    const content = documentRef.createElement("span");
    content.dataset.fileViewerRichText = "true";
    Object.assign(content.style, {
      display: "inline-block",
      maxWidth: "100%",
      minWidth: "0",
      whiteSpace: "inherit",
      wordBreak: "inherit"
    });
    style.richText.forEach((run) => {
      const segment = documentRef.createElement("span");
      segment.textContent = run.text;
      segment.dataset.fileViewerRichTextRun = "true";
      if (run.fontFamily) {
        segment.style.fontFamily = run.fontFamily;
      }
      if (run.fontSize) {
        segment.style.fontSize = `${run.fontSize}px`;
      }
      if (run.color) {
        segment.style.color = run.color;
      }
      if (run.bold) {
        segment.style.fontWeight = "bold";
      }
      if (run.italic) {
        segment.style.fontStyle = "italic";
      }
      const decorations = [
        run.underline ? "underline" : "",
        run.strike ? "line-through" : ""
      ].filter(Boolean);
      if (decorations.length) {
        segment.style.textDecoration = decorations.join(" ");
      }
      if (run.verticalAlign) {
        segment.style.verticalAlign = run.verticalAlign;
      }
      content.appendChild(segment);
    });
    text.appendChild(content);
  } else {
    text.textContent = getTextValue(value);
  }
  return text;
};
var applyOverflowLayout = (text, overflowLayout) => {
  if (!overflowLayout) {
    return;
  }
  Object.assign(text.style, {
    position: "absolute",
    left: `${overflowLayout.left}px`,
    top: "0",
    width: `${overflowLayout.width}px`,
    overflow: "hidden",
    textOverflow: "clip"
  });
};
var renderCellOverlay = (cellEl, borderStyle, textStyle, textValue, renderText, overflowLayout, zoomScale) => {
  const documentRef = cellEl.ownerDocument;
  cellEl.replaceChildren();
  Object.assign(cellEl.style, {
    pointerEvents: "none",
    overflow: overflowLayout ? "hidden" : "visible",
    background: "transparent"
  });
  const fragment = documentRef.createDocumentFragment();
  if (renderText) {
    const text = createTextLayer(documentRef, textValue, textStyle, scaleNumber(CELL_PADDING, zoomScale));
    applyOverflowLayout(text, overflowLayout);
    fragment.appendChild(text);
  }
  if (borderStyle.borderTop) {
    fragment.appendChild(createBorderLine(documentRef, "top", borderStyle.borderTop));
  }
  if (borderStyle.borderRight) {
    fragment.appendChild(createBorderLine(documentRef, "right", borderStyle.borderRight));
  }
  if (borderStyle.borderBottom) {
    fragment.appendChild(createBorderLine(documentRef, "bottom", borderStyle.borderBottom));
  }
  if (borderStyle.borderLeft) {
    fragment.appendChild(createBorderLine(documentRef, "left", borderStyle.borderLeft));
  }
  cellEl.appendChild(fragment);
};
var normalizeRichTextRuns = (value) => {
  if (!Array.isArray(value)) {
    return void 0;
  }
  const runs = value.flatMap((candidate) => {
    if (!candidate || typeof candidate !== "object") {
      return [];
    }
    const run = candidate;
    if (typeof run.text !== "string" || !run.text) {
      return [];
    }
    const fontSize = typeof run.fontSize === "number" && Number.isFinite(run.fontSize) && run.fontSize > 0 ? run.fontSize : void 0;
    return [{
      text: run.text,
      ...typeof run.fontFamily === "string" && run.fontFamily ? { fontFamily: run.fontFamily } : {},
      ...fontSize ? { fontSize } : {},
      ...typeof run.color === "string" && run.color ? { color: run.color } : {},
      ...run.bold ? { bold: true } : {},
      ...run.italic ? { italic: true } : {},
      ...run.underline ? { underline: true } : {},
      ...run.strike ? { strike: true } : {},
      ...run.verticalAlign === "sub" || run.verticalAlign === "super" ? { verticalAlign: run.verticalAlign } : {}
    }];
  });
  return runs.length ? runs : void 0;
};
var normalizeCellStyle = (meta) => {
  if (!meta) {
    return void 0;
  }
  const style = meta.style || {};
  const nextStyle = {};
  const richText = normalizeRichTextRuns(meta.richText);
  if (richText) {
    nextStyle.richText = richText;
  }
  if (style.backgroundColor) {
    nextStyle.backgroundColor = style.backgroundColor;
  }
  if (style.color) {
    nextStyle.color = style.color;
  } else if (style.backgroundColor && tinycolor(style.backgroundColor).isDark()) {
    nextStyle.color = "#ffffff";
  }
  const font = buildFont(style);
  if (font) {
    nextStyle.font = font;
  } else if (style.backgroundColor && tinycolor(style.backgroundColor).isDark()) {
    nextStyle.font = `bold ${TABLE_FONT_SIZE}px ${TABLE_FONT_FAMILY}`;
  }
  const borderTop = getBorderSide(style, "Top");
  if (borderTop) {
    nextStyle.borderTop = borderTop;
  }
  const borderRight = getBorderSide(style, "Right");
  if (borderRight) {
    nextStyle.borderRight = borderRight;
  }
  const borderBottom = getBorderSide(style, "Bottom");
  if (borderBottom) {
    nextStyle.borderBottom = borderBottom;
  }
  const borderLeft = getBorderSide(style, "Left");
  if (borderLeft) {
    nextStyle.borderLeft = borderLeft;
  }
  const horizontalAlign = alignFromClassName(meta.className);
  if (horizontalAlign) {
    nextStyle.horizontalAlign = horizontalAlign;
  }
  const verticalAlign = verticalAlignFromClassName(meta.className);
  if (verticalAlign) {
    nextStyle.verticalAlign = verticalAlign;
  }
  if (hasClassName(meta.className, "htWrap")) {
    nextStyle.wrapText = true;
  }
  if (hasClassName(meta.className, "htShrink")) {
    nextStyle.shrinkToFit = true;
  }
  if (!nextStyle.richText?.length && !nextStyle.backgroundColor && !nextStyle.color && !nextStyle.font && !hasBorder(nextStyle) && !hasTextLayout(nextStyle)) {
    return void 0;
  }
  return nextStyle;
};
var createTableConfig = ({
  hostHeight,
  darkMode = false,
  resizableColumns = false,
  resizableRows = false,
  copySelection,
  searchCell,
  sheetDefaults,
  virtualState,
  zoomScale = 1
}) => {
  const normalizedScale = normalizeZoomScale(zoomScale);
  const scaledPadding = scaleNumber(CELL_PADDING, normalizedScale);
  const scaledHeaderHeight = scaleNumber(HEADER_HEIGHT, normalizedScale);
  const scaledCellHeight = scaleNumber(normalizeRowHeight(sheetDefaults.rowHeight, sheetDefaults.rowHeight), normalizedScale);
  const scaledCellWidth = scaleNumber(sheetDefaults.colWidth, normalizedScale);
  const headerStyle = getIndexCellStyle(normalizedScale, darkMode);
  const loadingStyle = getLoadingCellStyle(normalizedScale, darkMode);
  const spanMethod = ({ rowIndex, colIndex, column }) => {
    if (colIndex === 0) {
      return;
    }
    const key = getCellCacheKey(rowIndex, colIndex, column);
    if (virtualState.mergeCoveredMap.has(key)) {
      return { rowspan: 0, colspan: 0 };
    }
    const merge = virtualState.mergeStartMap.get(key);
    if (!merge) {
      return;
    }
    return {
      rowspan: merge.rowspan,
      colspan: merge.colspan
    };
  };
  const headerStyleMethod = () => headerStyle;
  const styleMethod = ({ row, rowIndex, colIndex, column }) => {
    if (colIndex === 0) {
      return headerStyle;
    }
    const currentRow = row;
    if (isHiddenVirtualRow(currentRow)) {
      return void 0;
    }
    if (getRowState(currentRow) !== RowState.Loaded) {
      return loadingStyle;
    }
    const style = scaleCellStyle(virtualState.cellCache.get(getCellCacheKey(rowIndex, colIndex, column)), normalizedScale);
    const match = searchCell?.(rowIndex, getDataColumnIndex(column, colIndex));
    return match ? { ...style, backgroundColor: match === "active" ? "#ffbf47" : "#fff1a8", color: "#202124" } : style;
  };
  const renderMethod = ({
    row,
    rowIndex,
    colIndex,
    column,
    value
  }) => {
    const currentRow = row;
    if (colIndex === 0 || isHiddenVirtualRow(currentRow) || getRowState(currentRow) !== RowState.Loaded) {
      return void 0;
    }
    const cellKey = getCellCacheKey(rowIndex, colIndex, column);
    if (virtualState.mergeCoveredMap.has(cellKey)) {
      return void 0;
    }
    const style = scaleCellStyle(virtualState.cellCache.get(cellKey), normalizedScale);
    const dataColIndex = getDataColumnIndex(column, colIndex);
    const measureDocument = typeof document === "undefined" ? void 0 : document;
    const overflowLayout = getExcelOverflowLayout(
      virtualState,
      currentRow,
      rowIndex,
      dataColIndex,
      column,
      style,
      value,
      normalizedScale,
      measureDocument
    );
    const mirror = !hasRenderableValue(value) ? getLeftOverflowMirror(
      virtualState,
      currentRow,
      rowIndex,
      dataColIndex,
      normalizedScale,
      measureDocument
    ) : void 0;
    const match = searchCell?.(rowIndex, dataColIndex);
    const renderText = shouldRenderTextInOverlay(style, column) || !!overflowLayout || !!mirror || !!match;
    if (!hasBorder(style) && !renderText) {
      return void 0;
    }
    return ((cellEl) => {
      const baseStyle = {
        ...style || {},
        font: style?.font || getBodyFont(normalizedScale),
        color: match ? "#202124" : style?.color,
        horizontalAlign: style?.horizontalAlign || column?.align,
        verticalAlign: style?.verticalAlign || column?.verticalAlign
      };
      const collapsedStyle = hasBorder(style) ? getCollapsedBorderStyle(virtualState, rowIndex, dataColIndex, baseStyle, normalizedScale) : baseStyle;
      renderCellOverlay(
        cellEl,
        collapsedStyle,
        mirror?.style || collapsedStyle,
        mirror ? mirror.value : value,
        renderText,
        mirror?.overflowLayout || overflowLayout,
        normalizedScale
      );
      cellEl.style.boxShadow = match === "active" ? "inset 0 0 0 2px #9a5700" : "";
      if (match) {
        cellEl.dataset.spreadsheetSearch = match;
        cellEl.dataset.spreadsheetRow = `${rowIndex}`;
        cellEl.dataset.spreadsheetCol = `${dataColIndex}`;
        cellEl.style.background = match === "active" ? "#ffbf47" : "#fff1a8";
      } else {
        delete cellEl.dataset.spreadsheetSearch;
        delete cellEl.dataset.spreadsheetRow;
        delete cellEl.dataset.spreadsheetCol;
      }
    });
  };
  return {
    ROW_KEY: ROW_KEY_FIELD,
    DISABLED: true,
    HEIGHT: Math.max(hostHeight, 240),
    MAX_HEIGHT: Math.max(hostHeight, 240),
    HEADER_HEIGHT: scaledHeaderHeight,
    CELL_HEIGHT: scaledCellHeight,
    CELL_WIDTH: scaledCellWidth,
    CELL_PADDING: scaledPadding,
    CELL_LINE_HEIGHT,
    COLUMNS_VERTICAL_ALIGN: "middle",
    HEADER_FONT: getHeaderFont(normalizedScale),
    BODY_FONT: getBodyFont(normalizedScale),
    BORDER_RADIUS: 0,
    BORDER_COLOR: darkMode ? EXCEL_DARK_GRID : EXCEL_GRID,
    HEADER_BG_COLOR: darkMode ? EXCEL_DARK_HEADER_BG : EXCEL_HEADER_BG,
    BODY_BG_COLOR: darkMode ? EXCEL_DARK_BODY_BG : "#ffffff",
    HEADER_TEXT_COLOR: darkMode ? EXCEL_DARK_HEADER_TEXT : EXCEL_HEADER_TEXT,
    BODY_TEXT_COLOR: darkMode ? EXCEL_DARK_BODY_TEXT : "#202124",
    READONLY_COLOR: darkMode ? EXCEL_DARK_BODY_BG : "#ffffff",
    READONLY_TEXT_COLOR: darkMode ? EXCEL_DARK_BODY_TEXT : "#202124",
    EDIT_BG_COLOR: darkMode ? "#18212f" : "#ffffff",
    PLACEHOLDER_COLOR: darkMode ? "#94a3b8" : "#8a94a3",
    SCROLLER_COLOR: darkMode ? "#475569" : "#c1c7d0",
    SCROLLER_FOCUS_COLOR: darkMode ? "#64748b" : "#9aa0a6",
    SELECT_ROW_COL_BG_COLOR: EXCEL_GREEN_SOFT,
    SELECT_AREA_COLOR: "rgba(33, 163, 102, 0.14)",
    SELECT_BORDER_COLOR: EXCEL_GREEN,
    AUTOFILL_POINT_BORDER_COLOR: EXCEL_GREEN,
    ENABLE_SELECTOR: true,
    ENABLE_SELECTOR_SINGLE: false,
    ENABLE_SELECTOR_SPAN_COL: true,
    ENABLE_SELECTOR_SPAN_ROW: true,
    ENABLE_SELECTOR_ALL_ROWS: true,
    ENABLE_SELECTOR_ALL_COLS: true,
    SELECTOR_AREA_MIN_X: DATA_AREA_MIN_COL_INDEX,
    ENABLE_CONTEXT_MENU: false,
    ENABLE_HEADER_CONTEXT_MENU: false,
    ENABLE_AUTOFILL: true,
    ENABLE_AUTOFILL_SPAN_COL: true,
    ENABLE_AUTOFILL_SPAN_ROW: true,
    ENABLE_PASTER: false,
    ENABLE_HISTORY: false,
    ENABLE_RESIZE_COLUMN: resizableColumns,
    ENABLE_RESIZE_COLUMN_TEXT: resizableColumns,
    RESIZE_COLUMN_LINE_COLOR: EXCEL_GREEN,
    RESIZE_COLUMN_TEXT_BG_COLOR: EXCEL_GREEN,
    RESIZE_COLUMN_MIN_WIDTH: RESIZABLE_COLUMN_MIN_WIDTH,
    ENABLE_RESIZE_ROW: resizableRows,
    RESIZE_ROW_LINE_COLOR: EXCEL_GREEN,
    RESIZE_ROW_MIN_HEIGHT: scaleNumber(RESIZABLE_ROW_MIN_HEIGHT, normalizedScale),
    ENABLE_KEYBOARD: true,
    // The table finder only indexes loaded rows and competes with the viewer's
    // workbook-wide search shortcut. Keep one search owner for all integrations.
    ENABLE_FINDER: false,
    ENABLE_COPY: true,
    BEFORE_COPY_METHOD: copySelection ? (params) => {
      copySelection(params);
      return void 0;
    } : void 0,
    // 预览态只开放“拖动扩选”的交互，不允许真正写回单元格内容。
    BEFORE_AUTOFILL_DATA_METHOD: () => [],
    SPAN_METHOD: spanMethod,
    HEADER_CELL_STYLE_METHOD: headerStyleMethod,
    BODY_CELL_STYLE_METHOD: styleMethod,
    BODY_CELL_RENDER_METHOD: renderMethod,
    BODY_CELL_FORMATTER_METHOD: ({ row, rowIndex, colIndex, column, value }) => {
      if (isHiddenVirtualRow(row)) {
        return "";
      }
      if (colIndex === 0) {
        const displayIndex = rowIndex + 1 - virtualState.indexOffset;
        return displayIndex > 0 ? `${displayIndex}` : "";
      }
      if (getRowState(row) !== RowState.Loaded) {
        return "";
      }
      const currentRow = row;
      const style = scaleCellStyle(virtualState.cellCache.get(getCellCacheKey(rowIndex, colIndex, column)), normalizedScale);
      const dataColIndex = getDataColumnIndex(column, colIndex);
      const measureDocument = typeof document === "undefined" ? void 0 : document;
      const overflowLayout = getExcelOverflowLayout(
        virtualState,
        currentRow,
        rowIndex,
        dataColIndex,
        column,
        style,
        value,
        normalizedScale,
        measureDocument
      );
      const mirror = !hasRenderableValue(value) ? getLeftOverflowMirror(
        virtualState,
        currentRow,
        rowIndex,
        dataColIndex,
        normalizedScale,
        measureDocument
      ) : void 0;
      if (shouldRenderTextInOverlay(style, column) || overflowLayout || mirror || searchCell?.(rowIndex, dataColIndex)) {
        return "";
      }
      if (value === null || value === void 0) {
        return "";
      }
      return `${value}`;
    }
  };
};

// packages/renderers/spreadsheet/src/spreadsheet/viewport.ts
var GRID_FORMATS = /* @__PURE__ */ new Set(["xlsx", "xltx", "xlsm", "xltm", "xlsb", "xls", "xlt", "xla", "xlam", "csv", "tsv", "ods", "fods", "numbers", "et", "ett", "dbf"]);
var shouldFillSpreadsheetViewport = (enabled, type = "") => enabled !== false && GRID_FORMATS.has(type.toLowerCase().replace(/^\./, ""));
var columnLabel = (index) => {
  let value = index + 1;
  let label = "";
  while (value > 0) {
    value -= 1;
    label = String.fromCharCode(65 + value % 26) + label;
    value = Math.floor(value / 26);
  }
  return label;
};
var SpreadsheetViewportFill = class {
  sourceRows;
  rows = [];
  sourceColumns;
  columns = [];
  build(state, width, height, zoom) {
    const scale = (value) => Math.max(1, Math.round(value * zoom));
    const rowHeight = scale(normalizeRowHeight(state.defaults.rowHeight, state.defaults.rowHeight));
    const columnWidth = Math.max(1, Math.ceil(state.defaults.colWidth));
    let contentHeight = scale(HEADER_HEIGHT) + state.totalRows * rowHeight;
    state.rowHeightCache.forEach((value, index) => {
      if (index < state.totalRows) contentHeight += Math.max(0.1, Math.round(value * zoom)) - rowHeight;
    });
    const contentWidth = getDisplayColumns(state.columns, zoom).reduce((sum, column) => sum + (column.hide ? 0 : Number(column.width) || 0), 0);
    const extraRows = Math.min(
      Math.max(0, 1048576 - state.totalRows),
      Math.max(0, Math.ceil((height - contentHeight) / rowHeight))
    );
    const extraColumns = Math.min(
      Math.max(0, 16384 - state.totalCols),
      Math.max(0, Math.ceil((width - contentWidth) / scale(columnWidth)))
    );
    if (this.sourceRows !== state.rows || this.rows.length !== state.rows.length + extraRows) {
      this.sourceRows = state.rows;
      this.rows = extraRows ? state.rows.concat(Array.from({ length: extraRows }, (_, offset) => ({
        [ROW_KEY_FIELD]: `viewport-${state.totalRows + offset}`,
        [ROW_STATE_FIELD]: RowState.Loaded
      }))) : state.rows;
    }
    if (this.sourceColumns !== state.columns || this.columns.length !== state.columns.length + extraColumns) {
      this.sourceColumns = state.columns;
      this.columns = extraColumns ? state.columns.concat(Array.from({ length: extraColumns }, (_, offset) => ({
        key: getDataKey(state.totalCols + offset),
        title: columnLabel(state.totalCols + offset),
        width: columnWidth,
        minWidth: columnWidth,
        maxWidth: columnWidth,
        widthFillDisable: true,
        headerAlign: "center",
        headerVerticalAlign: "middle",
        align: "left",
        verticalAlign: "middle"
      }))) : state.columns;
    }
    for (let index = state.totalRows; index < this.rows.length; index += 1) this.rows[index]._height = rowHeight;
    return { rows: this.rows, columns: this.columns };
  }
};

// packages/renderers/spreadsheet/src/spreadsheet.ts
var EXCEL_IMAGE_SCROLLBAR_GUARD = 18;
var E_VIRT_TABLE_STYLE_MARKERS = [
  ".e-virt-table-container",
  ".e-virt-table-overlayer",
  ".e-virt-table-editor",
  ".e-virt-table-context-menu"
];
var SPREADSHEET_STYLE_SCOPE = ".excel-wrapper[data-file-viewer-spreadsheet-root]";
var E_VIRT_TABLE_ROTATE_KEYFRAME = "file-viewer-e-virt-table-rotate";
var enableEVirtTableShadowEventTargeting = (context) => {
  const isNativeTarget = context.isTarget.bind(context);
  context.isTarget = (event) => {
    if (isNativeTarget(event)) {
      return true;
    }
    const path = typeof event.composedPath === "function" ? event.composedPath() : [];
    return path.includes(context.containerElement);
  };
};
var spreadsheetStyle = `
.excel-wrapper{position:relative;width:100%;height:100%;display:flex;flex-direction:column;background:var(--file-viewer-render-surface-background,#fff);color:#172033;font-family:Aptos,'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif}
.excel-wrapper *{box-sizing:border-box}
.excel-wrapper .table-wrapper{position:relative;width:100%;flex:1;min-height:0;background:#fff;overflow:hidden}
.excel-wrapper .table-host{position:absolute;inset:0}
.excel-wrapper .table-target{width:100%;height:100%}
.excel-wrapper .table-host .e-virt-table-container,.excel-wrapper .table-host .e-virt-table-stage{width:100%!important}
.excel-wrapper .table-host .e-virt-table-container{height:100%!important}
.excel-wrapper .table-host .e-virt-table-stage{overflow:hidden}
.excel-wrapper .sheet-loading{position:absolute;right:18px;bottom:18px;z-index:20;display:inline-flex;align-items:center;gap:8px;padding:10px 14px;border-radius:14px;background:rgba(33,163,102,.1);border:1px solid rgba(33,163,102,.2);box-shadow:0 8px 20px rgba(33,163,102,.12);color:#1a7f50;font-size:12px;font-weight:700;pointer-events:none}
.excel-wrapper .sheet-loading-dot{width:8px;height:8px;flex-shrink:0;border-radius:999px;background:#21a366;box-shadow:0 0 0 6px rgba(33,163,102,.12);animation:file-viewer-spreadsheet-loading-pulse 1.2s ease-in-out infinite}
.excel-wrapper .sheet-loading-summary{color:#5f6368}
.excel-wrapper .excel-image-viewport{position:absolute;z-index:35;overflow:hidden;pointer-events:none}
.excel-wrapper .excel-image-layer{position:absolute;inset:0 auto auto 0;width:0;height:0;transform-origin:0 0;will-change:transform}
.excel-wrapper .excel-image{position:absolute;display:block;max-width:none;height:auto;object-fit:contain;user-select:none}
.excel-wrapper .excel-chart{position:absolute;display:block;max-width:none;overflow:hidden;background:#fff;box-shadow:0 1px 3px rgba(15,23,42,.08);user-select:none}
.excel-wrapper .excel-chart svg{display:block;width:100%;height:100%;overflow:visible}
.excel-wrapper .excel-image-lightbox{position:absolute;inset:0;z-index:1200;display:flex;align-items:center;justify-content:center;padding:clamp(16px,4vw,48px);background:rgba(15,23,42,.9);box-sizing:border-box;opacity:0;visibility:hidden;pointer-events:none;transition:opacity .18s ease,visibility 0s linear .18s}
.excel-wrapper .excel-image-lightbox[data-open='true']{opacity:1;visibility:visible;pointer-events:auto;transition-delay:0s}
.excel-wrapper .excel-image-lightbox img{display:block;max-width:100%;max-height:100%;object-fit:contain;background:#fff;box-shadow:0 30px 80px rgba(0,0,0,.4);transform:scale(.985);transition:transform .18s ease;user-select:none}
.excel-wrapper .excel-image-lightbox[data-open='true'] img{transform:scale(1)}
.excel-wrapper .excel-image-lightbox button{position:absolute;top:16px;right:16px;display:grid;width:40px;height:40px;place-items:center;padding:0;border:1px solid rgba(255,255,255,.7);border-radius:999px;background:rgba(255,255,255,.96);color:#172033;font:400 27px/1 Arial,sans-serif;cursor:pointer;box-shadow:0 12px 28px rgba(0,0,0,.24);transition:background-color .14s ease,transform .14s ease}
.excel-wrapper .excel-image-lightbox button:hover{background:#fff;transform:scale(1.04)}
.excel-wrapper .excel-image-lightbox button:focus-visible{outline:3px solid #60a5fa;outline-offset:2px}
.excel-wrapper .loading{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,.96);z-index:999;backdrop-filter:blur(6px)}
.excel-wrapper .loading-card{width:min(100%,460px);display:flex;align-items:center;gap:18px;padding:22px;border-radius:24px;background:rgba(255,255,255,.92);border:1px solid rgba(33,163,102,.1);box-shadow:0 22px 48px rgba(18,36,27,.12)}
.excel-wrapper .loading-brand{flex-shrink:0;width:78px;height:78px;display:flex;align-items:center;justify-content:center;border-radius:22px;background:linear-gradient(135deg,rgba(33,163,102,.14),rgba(33,163,102,.04));color:#1a7f50;font-size:18px;font-weight:900;letter-spacing:0}
.excel-wrapper .loading-copy{min-width:0;flex:1}
.excel-wrapper .loading-kicker{display:block;color:#21a366;font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase}
.excel-wrapper .loading-copy strong{display:block;margin-top:6px;color:#183828;font-size:20px;line-height:1.3}
.excel-wrapper .loading-copy p{margin:8px 0 0;color:#64748b;font-size:13px;line-height:1.5}
.excel-wrapper .loading-spinner{width:28px;height:28px;border-radius:999px;border:3px solid rgba(33,163,102,.16);border-top-color:#21a366;animation:file-viewer-spreadsheet-loading-spin .8s linear infinite}
.excel-wrapper .error{position:absolute;left:50%;top:50%;z-index:1000;transform:translate(-50%,-50%);max-width:min(520px,calc(100% - 48px));padding:16px 18px;border-radius:16px;background:#fff7ed;color:#9a3412;border:1px solid rgba(234,88,12,.18);box-shadow:0 18px 42px rgba(154,52,18,.12);font-size:14px;line-height:1.6}
.excel-wrapper .toolbar{min-height:44px;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:8px 12px;border-top:1px solid #e5e7eb;background:#f8fafc}
.excel-wrapper .btn-group{min-width:0;max-width:100%;flex:1 1 auto;display:flex;align-items:center;gap:6px;overflow-x:auto;overflow-y:hidden;scrollbar-gutter:stable;scrollbar-width:thin;overscroll-behavior-x:contain}
.excel-wrapper .sheet-tab{flex:0 0 auto;width:max-content;min-width:72px;max-width:min(260px,70vw);height:30px;border:1px solid transparent;border-radius:8px;padding:0 12px;background:transparent;color:#526173;font:inherit;font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;cursor:pointer}
.excel-wrapper .sheet-tab:hover{background:#edf2f7}
.excel-wrapper .sheet-tab.active{border-color:rgba(33,163,102,.28);background:rgba(33,163,102,.12);color:#137347}
.excel-wrapper .summary{flex:0 0 auto;max-width:42%;overflow:hidden;color:#64748b;font-size:12px;font-weight:700;white-space:nowrap;text-overflow:ellipsis}
.excel-wrapper .hidden{display:none!important}
.excel-wrapper[data-spreadsheet-theme='dark']{color-scheme:dark;background:var(--file-viewer-render-surface-background,#0f172a);color:#e5e7eb}
.excel-wrapper[data-spreadsheet-theme='dark'] .table-wrapper{background:#111827}
.excel-wrapper[data-spreadsheet-theme='dark'] .toolbar{background:#111827;border-color:rgba(148,163,184,.22)}
.excel-wrapper[data-spreadsheet-theme='dark'] .sheet-tab{color:#cbd5e1}
.excel-wrapper[data-spreadsheet-theme='dark'] .sheet-tab:hover{background:#1f2937}
.excel-wrapper[data-spreadsheet-theme='dark'] .sheet-tab.active{border-color:rgba(52,211,153,.38);background:rgba(33,163,102,.2);color:#6ee7b7}
.excel-wrapper[data-spreadsheet-theme='dark'] .summary,.excel-wrapper[data-spreadsheet-theme='dark'] .sheet-loading-summary{color:#94a3b8}
.excel-wrapper[data-spreadsheet-theme='dark'] .loading{background:rgba(2,6,23,.9)}
.excel-wrapper[data-spreadsheet-theme='dark'] .loading-card{border-color:rgba(52,211,153,.2);background:rgba(17,24,39,.96);box-shadow:0 24px 58px rgba(0,0,0,.42)}
.excel-wrapper[data-spreadsheet-theme='dark'] .loading-copy strong{color:#f0fdf4}
.excel-wrapper[data-spreadsheet-theme='dark'] .loading-copy p{color:#94a3b8}
.excel-wrapper[data-spreadsheet-theme='dark'] .error{border-color:rgba(251,146,60,.28);background:#2a1710;color:#fdba74;box-shadow:0 20px 48px rgba(0,0,0,.36)}
@keyframes file-viewer-spreadsheet-loading-spin{to{transform:rotate(360deg)}}
@keyframes file-viewer-spreadsheet-loading-pulse{0%,100%{opacity:.55;transform:scale(.9)}50%{opacity:1;transform:scale(1)}}
@media (max-width:720px){.excel-wrapper .toolbar{align-items:stretch;flex-direction:column}.excel-wrapper .btn-group{flex:0 0 auto}.excel-wrapper .summary{max-width:none;white-space:normal}.excel-wrapper .sheet-loading{left:12px;right:12px;bottom:58px;justify-content:center}.excel-wrapper .loading-card{margin:18px;flex-direction:column;text-align:center}.excel-wrapper .excel-image-lightbox button{top:12px;right:12px}}
@media (prefers-reduced-motion:reduce){.excel-wrapper .excel-image-lightbox,.excel-wrapper .excel-image-lightbox img,.excel-wrapper .excel-image-lightbox button{transition:none}}
`;
var scopedSpreadsheetStyle = spreadsheetStyle.replace(
  /\.excel-wrapper/g,
  SPREADSHEET_STYLE_SCOPE
);
var isEVirtTableConstructor = (value) => {
  return typeof value === "function";
};
var asModuleRecord = (value) => {
  return value && typeof value === "object" ? value : null;
};
var getEVirtTableGlobalCandidate = () => {
  const globalRecord = typeof globalThis === "undefined" ? null : globalThis;
  return globalRecord?.EVirtTable;
};
var resolveEVirtTableConstructor = (module) => {
  const record = asModuleRecord(module);
  const defaultRecord = asModuleRecord(record?.default);
  const moduleExportsRecord = asModuleRecord(record?.["module.exports"]);
  const globalCandidate = getEVirtTableGlobalCandidate();
  const candidates = [
    module,
    record?.default,
    record?.EVirtTable,
    record?.["module.exports"],
    defaultRecord?.default,
    defaultRecord?.EVirtTable,
    moduleExportsRecord?.default,
    moduleExportsRecord?.EVirtTable,
    globalCandidate
  ];
  const constructor = candidates.find(isEVirtTableConstructor);
  if (!constructor) {
    const keys = record ? Object.keys(record).join(", ") : typeof module;
    throw new Error(`Unable to resolve e-virt-table constructor from module exports: ${keys}`);
  }
  return constructor;
};
var isEVirtTableStyleText = (value) => {
  return E_VIRT_TABLE_STYLE_MARKERS.every((marker) => value.includes(marker));
};
var collectEVirtTableStyleDocuments = (documentRef) => [
  documentRef,
  typeof document === "undefined" ? null : document
].filter((value, index, values) => !!value && values.indexOf(value) === index);
var collectStyleElements = (documents) => documents.flatMap(
  (candidateDocument) => Array.from(candidateDocument.head?.querySelectorAll("style") || [])
);
var loadedEVirtTableStyleText = "";
var resolveEVirtTableStyleText = (documentRef) => {
  const styles = collectStyleElements(collectEVirtTableStyleDocuments(documentRef));
  for (let index = styles.length - 1; index >= 0; index -= 1) {
    const cssText = styles[index]?.textContent || "";
    if (isEVirtTableStyleText(cssText)) {
      return cssText;
    }
  }
  return "";
};
var loadEVirtTable = async (documentRef) => {
  const documents = collectEVirtTableStyleDocuments(documentRef);
  const stylesBeforeImport = new Set(collectStyleElements(documents));
  const module = await import("./index.es-KPAU56EJ.js");
  const injectedStyles = collectStyleElements(documents).filter((style) => !stylesBeforeImport.has(style) && isEVirtTableStyleText(style.textContent || ""));
  const injectedStyle = injectedStyles[injectedStyles.length - 1];
  if (injectedStyle) {
    loadedEVirtTableStyleText = injectedStyle.textContent || "";
  }
  injectedStyles.forEach((style) => style.remove());
  return {
    constructor: resolveEVirtTableConstructor(module),
    // The vendor entry injects CSS while its dynamic import is evaluated.
    // Prefer that newly-created node so an app's independently loaded table
    // version cannot be mistaken for the renderer-owned dependency.
    styleText: loadedEVirtTableStyleText || resolveEVirtTableStyleText(documentRef)
  };
};
var scopeEVirtTableStyleText = (cssText, shadow) => {
  const rootScope = shadow ? `:host,${SPREADSHEET_STYLE_SCOPE}` : SPREADSHEET_STYLE_SCOPE;
  const darkScope = shadow ? `:host(.dark),${SPREADSHEET_STYLE_SCOPE}[data-spreadsheet-theme='dark']` : `${SPREADSHEET_STYLE_SCOPE}[data-spreadsheet-theme='dark']`;
  const scopeSelector = (selector) => {
    const normalized = selector.trim();
    if (normalized === ":root") {
      return rootScope;
    }
    if (normalized === ".dark") {
      return darkScope;
    }
    return `${SPREADSHEET_STYLE_SCOPE} ${normalized}`;
  };
  return cssText.replace(/@keyframes\s+rotate\b/g, `@keyframes ${E_VIRT_TABLE_ROTATE_KEYFRAME}`).replace(/animation:\s*rotate\b/g, `animation:${E_VIRT_TABLE_ROTATE_KEYFRAME}`).replace(
    /(^|})\s*(:root|\.dark|\.e-virt-table-[^{}]+)\{/g,
    (_match, boundary, selectorList) => {
      const scopedSelectors = selectorList.split(",").map(scopeSelector).join(",");
      return `${boundary}${scopedSelectors}{`;
    }
  );
};
var getTargetWindow = (target) => {
  return target.ownerDocument.defaultView;
};
var createSpreadsheetWorkerFactory = (target, _bufferByteLength, context) => () => {
  const WorkerCtor = getTargetWindow(target)?.Worker || (typeof Worker !== "undefined" ? Worker : void 0);
  if (!WorkerCtor) throw new Error("Spreadsheet preview requires a parsing worker.");
  const workerUrl = new URL("./sheet.worker.js", import.meta.url);
  return new BoundedSpreadsheetWorker(
    () => new WorkerCtor(workerUrl, { type: "module" }),
    context?.signal
  );
};
var createStyle = (documentRef, cssText = scopedSpreadsheetStyle) => {
  const style = documentRef.createElement("style");
  style.textContent = cssText;
  return style;
};
var createEVirtTableStyle = (documentRef, target, cssText) => {
  if (!cssText) {
    throw new Error(
      "Unable to resolve the e-virt-table stylesheet for the spreadsheet render surface."
    );
  }
  const rootNode = target.getRootNode();
  const ShadowRootCtor = target.ownerDocument.defaultView?.ShadowRoot;
  const shadow = !!ShadowRootCtor && rootNode instanceof ShadowRootCtor;
  const style = createStyle(documentRef, scopeEVirtTableStyleText(cssText, shadow));
  style.dataset.fileViewerVendorStyle = "e-virt-table";
  return style;
};
var setHidden = (element, hidden) => {
  element.classList.toggle("hidden", hidden);
};
var clampZoom = (value) => {
  return Math.min(
    SPREADSHEET_MAX_ZOOM,
    Math.max(SPREADSHEET_MIN_ZOOM, Number(value.toFixed(2)))
  );
};
var serializeSpreadsheetCopyCell = (value) => {
  if (value === null || value === void 0) {
    return "";
  }
  const text = `${value}`;
  return /[\t\r\n"]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};
var serializeSpreadsheetCopyData = (data) => {
  if (!Array.isArray(data)) {
    return serializeSpreadsheetCopyCell(data);
  }
  return data.map((row) => {
    if (!Array.isArray(row)) {
      return serializeSpreadsheetCopyCell(row);
    }
    return row.map(serializeSpreadsheetCopyCell).join("	");
  }).join("\n");
};
var copyTextWithTextareaFallback = (documentRef, text) => {
  const body = documentRef.body;
  if (!body || typeof documentRef.execCommand !== "function") {
    return false;
  }
  const activeElement = documentRef.activeElement;
  const textarea = documentRef.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "true");
  textarea.setAttribute("aria-hidden", "true");
  Object.assign(textarea.style, {
    position: "fixed",
    top: "0",
    left: "0",
    width: "1px",
    height: "1px",
    padding: "0",
    border: "0",
    opacity: "0",
    pointerEvents: "none"
  });
  body.appendChild(textarea);
  textarea.focus({ preventScroll: true });
  textarea.select();
  textarea.setSelectionRange(0, textarea.value.length);
  let copied = false;
  try {
    copied = documentRef.execCommand("copy");
  } finally {
    textarea.remove();
    activeElement?.focus?.({ preventScroll: true });
  }
  return copied;
};
var writeSpreadsheetClipboard = async (documentRef, text) => {
  const targetWindow = documentRef.defaultView;
  const clipboard = targetWindow?.navigator?.clipboard;
  const useAsyncClipboard = !!targetWindow?.isSecureContext && typeof clipboard?.writeText === "function";
  if (useAsyncClipboard) {
    try {
      await clipboard.writeText(text);
      return true;
    } catch {
      return copyTextWithTextareaFallback(documentRef, text);
    }
  }
  return copyTextWithTextareaFallback(documentRef, text);
};
var renderFileViewerSpreadsheet = async (buffer, target, type, context) => {
  const documentRef = target.ownerDocument;
  if (context?.signal?.aborted) throw new DOMException("Spreadsheet rendering was aborted.", "AbortError");
  const loadedEVirtTable = await loadEVirtTable(documentRef);
  if (context?.signal?.aborted) throw new DOMException("Spreadsheet rendering was aborted.", "AbortError");
  const EVirtTable = loadedEVirtTable.constructor;
  const t = createFileViewerTranslator(context?.options);
  const zoomEmitter = createFileViewerZoomChangeEmitter();
  const systemDark = documentRef.defaultView?.matchMedia?.("(prefers-color-scheme: dark)").matches ?? false;
  const darkMode = resolveFileViewerColorScheme(context?.options?.theme, systemDark) === "dark";
  const root = documentRef.createElement("div");
  root.className = "excel-wrapper";
  root.dataset.fileViewerSpreadsheetRoot = "true";
  root.dataset.spreadsheetTheme = darkMode ? "dark" : "light";
  root.dataset.viewerSearchProvider = "spreadsheet";
  root.dataset.viewerZoomProvider = "xlsx";
  const loading = documentRef.createElement("div");
  loading.className = "loading";
  const loadingCard = documentRef.createElement("div");
  loadingCard.className = "loading-card";
  const loadingBrand = documentRef.createElement("div");
  loadingBrand.className = "loading-brand";
  loadingBrand.textContent = "XLSX";
  const loadingCopy = documentRef.createElement("div");
  loadingCopy.className = "loading-copy";
  const loadingKicker = documentRef.createElement("span");
  loadingKicker.className = "loading-kicker";
  loadingKicker.textContent = t("spreadsheet.loading.kicker");
  const loadingTitle = documentRef.createElement("strong");
  loadingTitle.dataset.loadingTitle = "true";
  loadingTitle.textContent = t("spreadsheet.loading.title");
  const loadingHint = documentRef.createElement("p");
  loadingHint.textContent = t("spreadsheet.loading.hint");
  loadingCopy.append(loadingKicker, loadingTitle, loadingHint);
  const loadingSpinner = documentRef.createElement("span");
  loadingSpinner.className = "loading-spinner";
  loadingCard.append(loadingBrand, loadingCopy, loadingSpinner);
  loading.appendChild(loadingCard);
  const error = documentRef.createElement("div");
  error.className = "error hidden";
  const tableWrapper = documentRef.createElement("div");
  tableWrapper.className = "table-wrapper";
  const sheetLoading = documentRef.createElement("div");
  sheetLoading.className = "sheet-loading hidden";
  const sheetLoadingDot = documentRef.createElement("span");
  sheetLoadingDot.className = "sheet-loading-dot";
  const sheetLoadingText = documentRef.createElement("span");
  sheetLoadingText.textContent = t("spreadsheet.loading.streaming");
  const sheetLoadingSummary = documentRef.createElement("span");
  sheetLoadingSummary.className = "sheet-loading-summary";
  sheetLoading.append(sheetLoadingDot, sheetLoadingText, sheetLoadingSummary);
  const tableHostShell = documentRef.createElement("div");
  tableHostShell.className = "table-host";
  const tableHost = documentRef.createElement("div");
  tableHost.className = "table-target";
  const imageViewport = documentRef.createElement("div");
  imageViewport.className = "excel-image-viewport hidden";
  const imageLayer = documentRef.createElement("div");
  imageLayer.className = "excel-image-layer";
  imageViewport.appendChild(imageLayer);
  tableHostShell.append(tableHost, imageViewport);
  tableWrapper.append(sheetLoading, tableHostShell);
  const imageLightbox = documentRef.createElement("div");
  imageLightbox.className = "excel-image-lightbox";
  imageLightbox.dataset.open = "false";
  imageLightbox.setAttribute("role", "dialog");
  imageLightbox.setAttribute("aria-modal", "true");
  imageLightbox.setAttribute("aria-hidden", "true");
  const lightboxImage = documentRef.createElement("img");
  lightboxImage.alt = t("image.lightbox.alt");
  lightboxImage.draggable = false;
  const lightboxCloseButton = documentRef.createElement("button");
  lightboxCloseButton.type = "button";
  lightboxCloseButton.setAttribute("aria-label", t("image.lightbox.close"));
  lightboxCloseButton.textContent = "\xD7";
  imageLightbox.append(lightboxImage, lightboxCloseButton);
  const toolbar = documentRef.createElement("div");
  toolbar.className = "toolbar";
  const sheetTabsBar = documentRef.createElement("div");
  sheetTabsBar.className = "btn-group";
  sheetTabsBar.setAttribute("aria-label", t("spreadsheet.tabs.ariaLabel"));
  const summary = documentRef.createElement("div");
  summary.className = "summary";
  toolbar.append(sheetTabsBar, summary);
  root.append(loading, error, tableWrapper, toolbar, imageLightbox);
  target.replaceChildren(
    createEVirtTableStyle(documentRef, target, loadedEVirtTable.styleText),
    createStyle(documentRef),
    root
  );
  let sheets = [];
  let sheetIndex = 0;
  let errorMessage = "";
  let totalRows = 0;
  let totalCols = 0;
  let sheetDefaults = { ...DEFAULT_SHEET_DEFAULTS };
  let sheetInitializing = true;
  let hasInitialWindow = false;
  let loadedWindowCount = 0;
  let loadingWindowCount = 0;
  let sheetImages = [];
  let sheetCharts = [];
  let zoom = 1;
  let imageViewportState = {
    scrollX: 0,
    scrollY: 0,
    width: 0,
    height: 0
  };
  let loadingState = true;
  let virtualState = createEmptyVirtualState();
  const sheetStateCache = /* @__PURE__ */ new Map();
  const sheetImageCache = /* @__PURE__ */ new Map();
  const sheetChartCache = /* @__PURE__ */ new Map();
  let table = null;
  let resizeObserver = null;
  let resizeFrame = 0;
  let scrollFrame = 0;
  let layoutRefreshToken = 0;
  const layoutRefreshTimers = [];
  let viewportRange = { start: 0, end: 0 };
  let scrollDirection = 1;
  let lastScrollY = 0;
  let sheetSessionId = 0;
  let disposed = false;
  const imageSourceResolver = createSpreadsheetImageSourceResolver(documentRef);
  let imageLightboxPreviousFocus = null;
  let hasNotifiedFirstPaint = false;
  let hasAppliedDefaultInitialFit = false;
  let searchState = createEmptyFileViewerSearchState();
  let searchMatches = [];
  let searchCells = /* @__PURE__ */ new Set();
  let searchOptions = {};
  let searchRequestSequence = 0;
  let latestSearchRequest = 0;
  let pendingSearchJump = null;
  let pendingViewRestore = null;
  let lastViewScrollX = 0;
  let lastViewScrollY = 0;
  let resolveWorkbookReady = null;
  const workbookReady = new Promise((resolve) => {
    resolveWorkbookReady = resolve;
  });
  let resolveInitialRender;
  let rejectInitialRender;
  const initialRender = new Promise((resolve, reject) => {
    resolveInitialRender = resolve;
    rejectInitialRender = reject;
  });
  const resizableColumns = context?.options?.spreadsheet?.resizableColumns === true;
  const resizableRows = context?.options?.spreadsheet?.resizableRows === true;
  const fillViewport = shouldFillSpreadsheetViewport(
    context?.options?.spreadsheet?.fillViewport,
    type || context?.filename?.split(".").pop()
  );
  const viewportFill = new SpreadsheetViewportFill();
  let renderedRows = [];
  const controller = createFileViewerWorkerController(
    createSpreadsheetWorkerFactory(target, buffer.byteLength, context),
    { logErrors: false }
  );
  const pendingSearchRequests = /* @__PURE__ */ new Map();
  const getActiveSheet = () => sheets.find((sheet) => sheet.id === sheetIndex);
  const getSheetTabs = () => {
    const visible = sheets.filter((sheet) => !sheet.hidden);
    return visible.length ? visible : sheets;
  };
  const getActiveSheetId = () => sheetIndex ?? sheets[0]?.id;
  const rangeNavigation = createSpreadsheetRangeNavigation({
    ready: workbookReady,
    isVisibleSheet: (id) => sheets.some((sheet) => sheet.id === id && !sheet.hidden),
    getScale: () => zoom,
    getState: () => ({
      zoom: getZoomState(),
      scroll: readSpreadsheetScroll(),
      spreadsheet: { sheetId: getActiveSheetId() }
    }),
    restoreState: restoreSpreadsheetView,
    fit: (request) => fitSpreadsheet(request),
    onNavigate: () => {
      latestSearchRequest += 1;
    },
    jump: (range) => jumpToSpreadsheetCell({ sheetId: range.sheetId, row: range.startRow, col: range.startCol }),
    clearJump: () => {
      pendingSearchJump = null;
      const restore = pendingViewRestore;
      pendingViewRestore = null;
      restore?.resolve();
      table?.draw();
    }
  });
  const getColumnLabel = (column) => {
    let value = Math.max(0, column) + 1;
    let label = "";
    while (value > 0) {
      const remainder = (value - 1) % 26;
      label = String.fromCharCode(65 + remainder) + label;
      value = Math.floor((value - 1) / 26);
    }
    return label;
  };
  const createSpreadsheetSearchAnchor = (match, index) => ({
    id: `spreadsheet-cell-${match.sheet}-${match.row}-${match.col}`,
    index,
    line: match.row + 1,
    type: "block",
    label: `${match.sheetName}!${getColumnLabel(match.col)}${match.row + 1}`,
    text: match.text,
    top: match.row * sheetDefaults.rowHeight,
    left: match.col * sheetDefaults.colWidth,
    width: sheetDefaults.colWidth,
    height: sheetDefaults.rowHeight,
    spreadsheet: {
      sheetId: match.sheet,
      row: match.row,
      col: match.col
    }
  });
  const setSearchState = (query, matches, currentIndex = matches.length ? 0 : -1) => {
    const normalizedIndex = matches.length ? (currentIndex % matches.length + matches.length) % matches.length : -1;
    searchMatches = matches;
    searchCells = new Set(matches.map((match) => {
      const cell = match.anchor?.spreadsheet;
      return cell ? `${cell.sheetId}:${cell.row}:${cell.col}` : "";
    }));
    searchState = {
      query,
      total: matches.length,
      currentIndex: normalizedIndex,
      current: normalizedIndex >= 0 ? matches[normalizedIndex] : null,
      matches
    };
    table?.draw();
    return searchState;
  };
  const getSearchCell = (row, col) => {
    if (rangeNavigation.contains(getActiveSheetId(), row, col)) return "active";
    if (!searchCells.has(`${getActiveSheetId()}:${row}:${col}`)) return void 0;
    const current = searchState.current?.anchor?.spreadsheet;
    return current?.sheetId === getActiveSheetId() && current.row === row && current.col === col ? "active" : "match";
  };
  const getHostHeight = () => tableHost.clientHeight || 0;
  const showBlockingLoading = () => !errorMessage && !hasInitialWindow && (loadingState || sheetInitializing);
  const showStreamingLoading = () => !showBlockingLoading() && !errorMessage && hasInitialWindow && loadingWindowCount > 0;
  const scalePx = (value) => Math.max(1, Math.round(value * zoom));
  const scaleRowHeight = (value) => Math.max(0.1, Math.round(value * zoom));
  const closeImageLightbox = () => {
    if (imageLightbox.dataset.open !== "true") {
      return;
    }
    imageLightbox.dataset.open = "false";
    imageLightbox.setAttribute("aria-hidden", "true");
    delete imageLightbox.dataset.imageId;
    if (imageLightboxPreviousFocus?.isConnected) {
      imageLightboxPreviousFocus.focus({ preventScroll: true });
    }
    imageLightboxPreviousFocus = null;
  };
  const openImageLightbox = (image) => {
    imageLightboxPreviousFocus = documentRef.activeElement instanceof HTMLElement ? documentRef.activeElement : null;
    lightboxImage.src = image.src;
    void imageSourceResolver.resolve(image).then((source) => {
      if (!disposed && imageLightbox.dataset.imageId === image.id) {
        lightboxImage.src = source;
      }
    });
    imageLightbox.dataset.imageId = image.id;
    imageLightbox.dataset.open = "true";
    imageLightbox.setAttribute("aria-hidden", "false");
    lightboxCloseButton.focus({ preventScroll: true });
  };
  const containsViewportPoint = (item, x, y) => {
    const left = scalePx(item.left) - imageViewportState.scrollX;
    const top = scalePx(item.top) - imageViewportState.scrollY;
    const right = left + scalePx(item.width);
    const bottom = top + scalePx(item.height);
    return x >= left && x <= right && y >= top && y <= bottom;
  };
  const findImageAtViewportPoint = (clientX, clientY) => {
    const viewportRect = imageViewport.getBoundingClientRect();
    const x = clientX - viewportRect.left;
    const y = clientY - viewportRect.top;
    if (x < 0 || y < 0 || x > viewportRect.width || y > viewportRect.height) {
      return void 0;
    }
    if ([...sheetCharts].reverse().some((chart) => containsViewportPoint(chart, x, y))) {
      return void 0;
    }
    return [...sheetImages].reverse().find((image) => containsViewportPoint(image, x, y));
  };
  const handleImageDoubleClick = (event) => {
    const image = findImageAtViewportPoint(event.clientX, event.clientY);
    if (!image) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    openImageLightbox(image);
  };
  const handleImageLightboxClick = (event) => {
    if (event.target === imageLightbox) {
      closeImageLightbox();
    }
  };
  const handleImageLightboxKeyDown = (event) => {
    if (event.key === "Escape" && imageLightbox.dataset.open === "true") {
      event.preventDefault();
      closeImageLightbox();
    }
  };
  tableHostShell.addEventListener("dblclick", handleImageDoubleClick, true);
  imageLightbox.addEventListener("click", handleImageLightboxClick);
  lightboxCloseButton.addEventListener("click", closeImageLightbox);
  documentRef.addEventListener("keydown", handleImageLightboxKeyDown);
  const getSheetLoadingText = () => {
    if (!sheets.length) {
      return t("spreadsheet.state.parsingWorkbook");
    }
    const activeName = getActiveSheet()?.name;
    return activeName ? t("spreadsheet.state.preparingSheetNamed", { name: activeName }) : t("spreadsheet.state.preparingSheet");
  };
  const getCachedSummary = () => {
    if (!totalRows) {
      return "";
    }
    const cachedRows = Math.min(loadedWindowCount * WINDOW_SIZE, totalRows);
    return t("spreadsheet.state.cachedRows", {
      cached: cachedRows.toLocaleString(),
      total: totalRows.toLocaleString()
    });
  };
  const getStatusSummary = () => {
    const rows = totalRows || getActiveSheet()?.rowCount || 0;
    const cols = totalCols || getActiveSheet()?.colCount || 0;
    if (!rows) {
      return "";
    }
    if (!cols) {
      return t("spreadsheet.state.rows", { rows: rows.toLocaleString() });
    }
    return t("spreadsheet.state.rowsAndColumns", {
      rows: rows.toLocaleString(),
      cols: cols.toLocaleString()
    });
  };
  const getZoomState = () => ({
    scale: zoom,
    label: `${Math.round(zoom * 100)}%`,
    canZoomIn: zoom < SPREADSHEET_MAX_ZOOM,
    canZoomOut: zoom > SPREADSHEET_MIN_ZOOM,
    canReset: zoom !== 1,
    minScale: SPREADSHEET_MIN_ZOOM,
    maxScale: SPREADSHEET_MAX_ZOOM
  });
  const getImageViewportScrollbarGuard = () => {
    const tableContainer = tableHost.querySelector(".e-virt-table-container");
    const vertical = tableContainer ? Math.max(tableContainer.offsetWidth - tableContainer.clientWidth, 0) : 0;
    const horizontal = tableContainer ? Math.max(tableContainer.offsetHeight - tableContainer.clientHeight, 0) : 0;
    return {
      vertical: vertical || EXCEL_IMAGE_SCROLLBAR_GUARD,
      horizontal: horizontal || EXCEL_IMAGE_SCROLLBAR_GUARD
    };
  };
  const renderImages = () => {
    const margin = 240;
    const guard = getImageViewportScrollbarGuard();
    const width = Math.max(
      imageViewportState.width - scalePx(INDEX_COLUMN_WIDTH) - guard.vertical,
      0
    );
    const height = Math.max(
      imageViewportState.height - scalePx(HEADER_HEIGHT) - guard.horizontal,
      0
    );
    const visibleImages = sheetImages.filter((image) => {
      const x = scalePx(image.left) - imageViewportState.scrollX;
      const y = scalePx(image.top) - imageViewportState.scrollY;
      return x + scalePx(image.width) >= -margin && x <= width + margin && y + scalePx(image.height) >= -margin && y <= height + margin;
    });
    const visibleCharts = sheetCharts.filter((chart) => {
      const x = scalePx(chart.left) - imageViewportState.scrollX;
      const y = scalePx(chart.top) - imageViewportState.scrollY;
      return x + scalePx(chart.width) >= -margin && x <= width + margin && y + scalePx(chart.height) >= -margin && y <= height + margin;
    });
    setHidden(imageViewport, visibleImages.length === 0 && visibleCharts.length === 0);
    Object.assign(imageViewport.style, {
      left: `${scalePx(INDEX_COLUMN_WIDTH)}px`,
      top: `${scalePx(HEADER_HEIGHT)}px`,
      right: "auto",
      bottom: "auto",
      width: `${width}px`,
      height: `${height}px`
    });
    imageLayer.style.transform = `translate(${-imageViewportState.scrollX}px, ${-imageViewportState.scrollY}px)`;
    const imageElements = visibleImages.map((image, index) => {
      const element = documentRef.createElement("img");
      element.className = "excel-image";
      element.src = image.src;
      element.alt = image.id;
      element.draggable = false;
      Object.assign(element.style, {
        left: `${scalePx(image.left)}px`,
        top: `${scalePx(image.top)}px`,
        width: `${scalePx(image.width)}px`,
        height: `${scalePx(image.height)}px`
      });
      element.dataset.imageIndex = `${index}`;
      void imageSourceResolver.resolve(image).then((source) => {
        if (!disposed && element.isConnected && element.src !== source) {
          element.src = source;
        }
      });
      return element;
    });
    const chartElements = visibleCharts.map((chart) => {
      const element = renderSpreadsheetChart(documentRef, chart);
      Object.assign(element.style, {
        left: `${scalePx(chart.left)}px`,
        top: `${scalePx(chart.top)}px`,
        width: `${scalePx(chart.width)}px`,
        height: `${scalePx(chart.height)}px`
      });
      return element;
    });
    imageLayer.replaceChildren(...imageElements, ...chartElements);
  };
  const scrollActiveSheetIntoView = () => {
    requestAnimationFrame(() => {
      sheetTabsBar.querySelector(".sheet-tab.active")?.scrollIntoView({
        block: "nearest",
        inline: "center",
        behavior: "smooth"
      });
    });
  };
  const renderChrome = () => {
    setHidden(loading, !showBlockingLoading());
    const loadingTitle2 = loading.querySelector("[data-loading-title]");
    if (loadingTitle2) {
      loadingTitle2.textContent = getSheetLoadingText();
    }
    error.textContent = errorMessage;
    setHidden(error, !errorMessage);
    setHidden(sheetLoading, !showStreamingLoading());
    const cacheText = sheetLoading.querySelector(".sheet-loading-summary");
    if (cacheText) {
      cacheText.textContent = getCachedSummary();
    }
    summary.textContent = getStatusSummary();
    sheetTabsBar.replaceChildren(...getSheetTabs().map((sheet) => {
      const button = documentRef.createElement("button");
      button.type = "button";
      button.className = `sheet-tab${sheetIndex === sheet.id ? " active" : ""}`;
      button.title = sheet.name;
      button.textContent = sheet.name;
      button.setAttribute("aria-pressed", sheetIndex === sheet.id ? "true" : "false");
      button.addEventListener("click", () => handleSheet(sheet.id));
      return button;
    }));
    renderImages();
  };
  const setLoading = (value) => {
    loadingState = value;
    renderChrome();
  };
  const emitWorker = (type2, payload) => {
    setLoading(true);
    controller.emit(type2, payload);
  };
  const requestWorkbookSearch = (query, options) => new Promise((resolve, reject) => {
    const requestId = ++searchRequestSequence;
    pendingSearchRequests.set(requestId, { resolve, reject });
    controller.emit("searchWorkbook", {
      requestId,
      query,
      caseSensitive: options.caseSensitive === true,
      wholeWord: options.wholeWord === true,
      maxMatches: options.maxMatches
    });
  });
  const applyRowHeight = (row, baseHeight) => {
    row.__baseHeight = baseHeight;
    row._height = scaleRowHeight(baseHeight);
  };
  const syncScaledRowHeights = () => {
    virtualState.rowHeightCache.forEach((height, rowIndex) => {
      const row = virtualState.rows[rowIndex];
      if (row) {
        applyRowHeight(row, height);
      }
    });
  };
  const setZoom = (scale) => {
    zoom = clampZoom(scale);
    syncScaledRowHeights();
    syncTableLayout();
    zoomEmitter.emit();
    renderChrome();
    return getZoomState();
  };
  const getSpreadsheetContentSize = () => {
    const contentWidth = virtualState.columns.reduce((sum, column) => {
      const candidate = column;
      if (candidate.hide) {
        return sum;
      }
      const width = Number(candidate.width);
      return sum + (Number.isFinite(width) && width > 0 ? width : sheetDefaults.colWidth);
    }, 0);
    const defaultRowHeight = normalizeRowHeight(
      sheetDefaults.rowHeight,
      DEFAULT_SHEET_DEFAULTS.rowHeight
    );
    let explicitHeight = 0;
    let explicitRows = 0;
    virtualState.rowHeightCache.forEach((height) => {
      explicitHeight += normalizeRowHeight(height, defaultRowHeight);
      explicitRows += 1;
    });
    const contentHeight = HEADER_HEIGHT + explicitHeight + Math.max(0, virtualState.totalRows - explicitRows) * defaultRowHeight;
    return { contentWidth, contentHeight };
  };
  const resolveSpreadsheetScale = (request) => {
    const content = getSpreadsheetContentSize();
    const autoMode = request.mode === "auto";
    const viewportWidth = request.viewportWidth || tableHost.clientWidth || 0;
    const viewportHeight = request.viewportHeight || tableHost.clientHeight || 0;
    if (viewportWidth <= 0 || viewportHeight <= 0) {
      return void 0;
    }
    return resolveFileViewerFitScale({
      mode: autoMode ? "width" : request.mode,
      viewportWidth,
      viewportHeight,
      contentWidth: content.contentWidth,
      contentHeight: content.contentHeight,
      currentScale: zoom,
      minScale: request.minScale ?? SPREADSHEET_MIN_ZOOM,
      maxScale: request.maxScale ?? (autoMode ? 1 : SPREADSHEET_MAX_ZOOM)
    });
  };
  const fitSpreadsheet = (request) => {
    if (!virtualState.active || !virtualState.columns.length) {
      return {
        applied: false,
        mode: request.mode,
        resize: request.resize,
        source: request.source,
        reason: "pending",
        provider: "zoom"
      };
    }
    const scale = resolveSpreadsheetScale(request);
    if (!scale) {
      return {
        applied: false,
        mode: request.mode,
        resize: request.resize,
        source: request.source,
        reason: "unmeasurable",
        provider: "zoom"
      };
    }
    const state = setZoom(scale);
    return {
      applied: true,
      mode: request.mode,
      resize: request.resize,
      scale: state.scale,
      source: request.source,
      provider: "zoom"
    };
  };
  const applyDefaultInitialFit = () => {
    const explicitInitialScale = Number(
      context?.options?.initialViewState?.scale ?? context?.options?.initialViewState?.zoom?.scale
    );
    if (hasAppliedDefaultInitialFit || context?.options?.fit !== void 0 || Number.isFinite(explicitInitialScale) && explicitInitialScale > 0) {
      hasAppliedDefaultInitialFit = true;
      return;
    }
    const scale = resolveSpreadsheetScale({
      mode: "auto",
      resize: "initial",
      padding: 0,
      source: "initial",
      reason: "initial",
      viewportWidth: tableHost.clientWidth || target.clientWidth || 0,
      viewportHeight: tableHost.clientHeight || target.clientHeight || 0,
      container: tableHost
    });
    if (!scale || scale >= zoom) {
      if (scale) {
        hasAppliedDefaultInitialFit = true;
      }
      return;
    }
    zoom = clampZoom(scale);
    syncScaledRowHeights();
    zoomEmitter.emit();
    hasAppliedDefaultInitialFit = true;
  };
  registerFileViewerZoomProvider(root, {
    zoomIn: () => setZoom(zoom + 0.1),
    zoomOut: () => setZoom(zoom - 0.1),
    resetZoom: () => setZoom(1),
    setZoom,
    fit: fitSpreadsheet,
    getState: getZoomState,
    subscribe: zoomEmitter.subscribe
  });
  const syncWindowStats = () => {
    loadedWindowCount = virtualState.loadedWindows.size;
    loadingWindowCount = virtualState.loadingWindows.size;
    renderChrome();
  };
  const syncImageViewport = () => {
    imageViewportState = {
      scrollX: table?.ctx.scrollX || 0,
      scrollY: table?.ctx.scrollY || 0,
      width: tableHost.clientWidth || 0,
      height: tableHost.clientHeight || 0
    };
    renderImages();
  };
  const markCopiedSelection = (params) => {
    const selector = table?.ctx.selector;
    if (!selector) {
      return;
    }
    selector.xArrCopy = params.xArr.slice();
    selector.yArrCopy = params.yArr.slice();
    table?.ctx.emit?.("copyChange", {
      xArr: selector.xArrCopy,
      yArr: selector.yArrCopy,
      data: params.data
    });
    table?.ctx.emit?.("draw");
  };
  const copySpreadsheetSelection = (params) => {
    const text = serializeSpreadsheetCopyData(params.data);
    void writeSpreadsheetClipboard(documentRef, text).then((copied) => {
      if (copied) {
        markCopiedSelection(params);
        return;
      }
      console.error("Spreadsheet copy failed: clipboard fallback returned false.");
    }).catch((error2) => {
      console.error("Spreadsheet copy failed:", error2);
    });
  };
  const buildTableView = () => {
    const display = fillViewport && virtualState.active ? viewportFill.build(virtualState, tableHost.clientWidth, Math.max(getHostHeight(), 240), zoom) : { columns: virtualState.columns, rows: virtualState.rows };
    return {
      config: createTableConfig({
        hostHeight: getHostHeight(),
        darkMode,
        resizableColumns,
        resizableRows,
        copySelection: copySpreadsheetSelection,
        searchCell: getSearchCell,
        sheetDefaults,
        virtualState,
        zoomScale: zoom
      }),
      columns: getDisplayColumns(display.columns, zoom),
      rows: display.rows
    };
  };
  const resetViewportTracking = () => {
    viewportRange = { start: 0, end: 0 };
    scrollDirection = 1;
    lastScrollY = 0;
  };
  const ensureViewportWindows = (startRow, endRow) => {
    if (!virtualState.active || !virtualState.totalRows) {
      return;
    }
    collectWindowStarts({
      startRow,
      endRow,
      direction: scrollDirection,
      totalRows: virtualState.totalRows
    }).forEach((windowStart) => requestWindow(windowStart, true));
  };
  const scheduleViewportLoad = () => {
    if (!table || disposed) {
      return;
    }
    if (scrollFrame) {
      cancelAnimationFrame(scrollFrame);
    }
    scrollFrame = requestAnimationFrame(() => {
      scrollFrame = 0;
      if (!table || !virtualState.active || !virtualState.totalRows || disposed) {
        return;
      }
      const head = Math.max(table.ctx.body.headIndex || 0, 0);
      const tail = Math.max(table.ctx.body.tailIndex || head, head);
      const scrollY = table.ctx.scrollY || 0;
      const scrollX = table.ctx.scrollX || 0;
      if (scrollX !== lastViewScrollX || scrollY !== lastViewScrollY) {
        lastViewScrollX = scrollX;
        lastViewScrollY = scrollY;
        rangeNavigation.notify("scroll", "viewer");
      }
      scrollDirection = scrollY >= lastScrollY ? 1 : -1;
      lastScrollY = scrollY;
      viewportRange = { start: head, end: tail };
      syncImageViewport();
      ensureViewportWindows(head, tail);
    });
  };
  const ensureTable = () => {
    if (table) {
      return table;
    }
    table = new EVirtTable(tableHost, {
      data: [],
      columns: [],
      config: createTableConfig({
        hostHeight: getHostHeight(),
        darkMode,
        resizableColumns,
        resizableRows,
        copySelection: copySpreadsheetSelection,
        searchCell: getSearchCell,
        sheetDefaults,
        virtualState,
        zoomScale: zoom
      })
    });
    enableEVirtTableShadowEventTargeting(table.ctx);
    table.on("onScrollX", scheduleViewportLoad);
    table.on("onScrollY", scheduleViewportLoad);
    table.on("resize", scheduleViewportLoad);
    table.on("resizeColumnChange", handleColumnResizeChange);
    table.on("resizeRowChange", handleRowResizeChange);
    return table;
  };
  const renderTable = (instance2, resetScroll = false) => {
    const view = buildTableView();
    instance2.loadConfig(view.config);
    instance2.loadColumns(view.columns);
    instance2.loadData(view.rows);
    renderedRows = view.rows;
    instance2.draw();
    syncImageViewport();
    if (resetScroll) {
      requestAnimationFrame(() => {
        instance2.scrollTo(0, 0);
        instance2.draw();
        syncImageViewport();
        scheduleViewportLoad();
      });
      return;
    }
    scheduleViewportLoad();
  };
  function syncTableLayout() {
    const instance2 = ensureTable();
    const { config, columns, rows } = buildTableView();
    instance2.loadConfig(config);
    if (virtualState.active && columns.length) {
      instance2.loadColumns(columns);
    }
    if (fillViewport && virtualState.active && rows !== renderedRows) {
      instance2.loadData(rows);
      renderedRows = rows;
    }
    instance2.doLayout();
    instance2.draw();
    syncImageViewport();
    scheduleViewportLoad();
  }
  const clearScheduledLayoutRefresh = () => {
    layoutRefreshToken += 1;
    const view = getTargetWindow(target);
    while (layoutRefreshTimers.length) {
      const timer = layoutRefreshTimers.pop();
      if (timer !== void 0) {
        view?.clearTimeout(timer);
      }
    }
  };
  const refreshTableLayoutWhenVisible = () => {
    if (disposed || !table || !virtualState.active) {
      return;
    }
    const rect = tableHost.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    applyDefaultInitialFit();
    syncTableLayout();
  };
  const scheduleStableFirstPaintRefresh = () => {
    clearScheduledLayoutRefresh();
    const token = layoutRefreshToken;
    const view = getTargetWindow(target);
    if (!view) {
      return;
    }
    const delays = [0, 32, 120, 300, 700];
    delays.forEach((delay) => {
      const timer = view.setTimeout(() => {
        const index = layoutRefreshTimers.indexOf(timer);
        if (index >= 0) {
          layoutRefreshTimers.splice(index, 1);
        }
        view.requestAnimationFrame(() => {
          if (token !== layoutRefreshToken) {
            return;
          }
          refreshTableLayoutWhenVisible();
        });
      }, delay);
      layoutRefreshTimers.push(timer);
    });
    void documentRef.fonts?.ready.then(() => {
      if (token !== layoutRefreshToken) {
        return;
      }
      refreshTableLayoutWhenVisible();
    }).catch(() => {
    });
  };
  function setColumnWidthByKey(columns, key, width) {
    for (const column of columns) {
      if (`${column.key}` === key) {
        column.width = width;
        return true;
      }
      if (Array.isArray(column.children) && setColumnWidthByKey(column.children, key, width)) {
        return true;
      }
    }
    return false;
  }
  function clearTableResizableHeaderCache() {
    try {
      table?.setCustomHeader?.({ resizableData: {} }, true);
    } catch {
    }
  }
  function handleColumnResizeChange(event) {
    if (!resizableColumns || disposed) {
      return;
    }
    const key = event?.key === void 0 ? "" : `${event.key}`;
    const displayWidth = Number(event?.width);
    if (!key || key === INDEX_COLUMN_KEY || !Number.isFinite(displayWidth) || displayWidth <= 0) {
      return;
    }
    const baseWidth = Math.max(
      1,
      Math.round(displayWidth / Math.max(zoom, 0.01))
    );
    const changed = setColumnWidthByKey(
      virtualState.columns,
      key,
      Math.max(baseWidth, Math.round(RESIZABLE_COLUMN_MIN_WIDTH / Math.max(zoom, 1)))
    );
    if (!changed) {
      return;
    }
    const activeSheetId = getActiveSheetId();
    if (activeSheetId !== void 0) {
      sheetStateCache.set(activeSheetId, virtualState);
    }
    queueMicrotask(() => {
      if (disposed || !table) return;
      clearTableResizableHeaderCache();
      syncTableLayout();
    });
  }
  function handleRowResizeChange(event) {
    if (!resizableRows || disposed) {
      return;
    }
    const rowIndex = Number(event?.rowIndex);
    const displayHeight = Number(event?.height);
    if (!Number.isInteger(rowIndex) || rowIndex < 0 || !Number.isFinite(displayHeight) || displayHeight <= 0) {
      return;
    }
    const row = virtualState.rows[rowIndex];
    if (!row) {
      if (fillViewport && renderedRows[rowIndex]) {
        queueMicrotask(() => {
          if (!disposed && table) syncTableLayout();
        });
      }
      return;
    }
    const baseHeight = normalizeRowHeight(
      Math.max(
        RESIZABLE_ROW_MIN_HEIGHT,
        Math.round(displayHeight / Math.max(zoom, 0.01))
      ),
      virtualState.defaults.rowHeight
    );
    applyRowHeight(row, baseHeight);
    virtualState.rowHeightOverrides.set(rowIndex, baseHeight);
    virtualState.rowHeightCache.set(rowIndex, baseHeight);
    const activeSheetId = getActiveSheetId();
    if (activeSheetId !== void 0) {
      sheetStateCache.set(activeSheetId, virtualState);
    }
    syncTableLayout();
  }
  function requestWindow(startRow = 0, silent = true) {
    const sheetId = getActiveSheetId();
    if (sheetId === void 0) {
      return;
    }
    const windowStart = clampWindowStart(startRow, virtualState.totalRows);
    if (virtualState.loadedWindows.has(windowStart) || virtualState.loadingWindows.has(windowStart)) {
      return;
    }
    virtualState.loadingWindows.add(windowStart);
    syncWindowStats();
    if (virtualState.active) {
      markWindowState(virtualState.rows, virtualState.totalRows, windowStart, RowState.Loading);
      table?.draw();
    }
    errorMessage = "";
    emitWorker("parseSheet", {
      sheet: sheetId,
      startRow: windowStart,
      pageSize: WINDOW_SIZE,
      sessionId: sheetSessionId
    });
    if (silent) {
      loadingState = false;
      renderChrome();
    }
  }
  const initializeVirtualSheet = (ws) => {
    const meta = ws.meta;
    if (!meta) {
      return;
    }
    const { columns, dataKeys } = buildColumns(ws);
    virtualState = {
      ...createEmptyVirtualState(),
      active: true,
      totalRows: meta.totalRows,
      totalCols: meta.totalCols,
      indexOffset: detectIndexOffset(ws),
      defaults: ws.defaults,
      dataKeys,
      rows: buildRows(meta.totalRows),
      columns
    };
    sheetDefaults = ws.defaults;
    totalRows = meta.totalRows;
    totalCols = meta.totalCols;
    syncWindowStats();
  };
  const clearVirtualRow = (row) => {
    virtualState.dataKeys.forEach((key) => {
      delete row[key];
    });
  };
  const applyStructureRowHeights = (rowHeights) => {
    if (!Array.isArray(rowHeights)) {
      return;
    }
    rowHeights.forEach((rawHeight, absoluteRow) => {
      if (rawHeight === void 0) {
        return;
      }
      const row = virtualState.rows[absoluteRow];
      if (!row) {
        return;
      }
      const height = virtualState.rowHeightOverrides.get(absoluteRow) ?? normalizeRowHeight(rawHeight, virtualState.defaults.rowHeight);
      applyRowHeight(row, height);
      virtualState.rowHeightCache.set(absoluteRow, height);
    });
  };
  const applyWindowRows = (ws) => {
    const meta = ws.meta;
    if (!meta) {
      return;
    }
    const rowIndexes = [];
    const endRow = Math.min(meta.endRow, virtualState.totalRows);
    for (let absoluteRow = meta.startRow; absoluteRow < endRow; absoluteRow += 1) {
      const row = virtualState.rows[absoluteRow];
      const relativeRow = absoluteRow - meta.startRow;
      if (!row) {
        continue;
      }
      clearVirtualRow(row);
      const data = ws.data?.[relativeRow] || [];
      data.forEach((value, colIndex) => {
        if (value === "" || value === null || value === void 0) {
          return;
        }
        row[getDataKey(colIndex)] = value;
      });
      const windowHeight = getRowHeight(ws.rowHeights, relativeRow, virtualState.defaults.rowHeight);
      const height = virtualState.rowHeightOverrides.get(absoluteRow) ?? normalizeRowHeight(
        getRowHeight(ws.structure?.rowHeights, absoluteRow, windowHeight),
        virtualState.defaults.rowHeight
      );
      applyRowHeight(row, height);
      row[ROW_STATE_FIELD] = RowState.Loaded;
      virtualState.rowHeightCache.set(absoluteRow, height);
      rowIndexes.push(absoluteRow);
    }
    virtualState.windowRows.set(meta.startRow, rowIndexes);
  };
  const applyWindowCells = (ws) => {
    const meta = ws.meta;
    if (!meta) {
      return;
    }
    const keys = [];
    Object.entries(ws.cell || {}).forEach(([key, value]) => {
      const [row, col] = key.split("-").map(Number);
      const absoluteKey = displayCellKey(meta.startRow + row, col + 1);
      const style = normalizeCellStyle(value);
      if (!style) {
        return;
      }
      virtualState.cellCache.set(absoluteKey, style);
      keys.push(absoluteKey);
    });
    virtualState.windowCells.set(meta.startRow, keys);
  };
  const setSheetMerges = (merges) => {
    virtualState.mergeStartMap.clear();
    virtualState.mergeCoveredMap.clear();
    merges.forEach((merge) => {
      const startKey = displayCellKey(merge.row, merge.col + 1);
      virtualState.mergeStartMap.set(startKey, {
        ...merge,
        col: merge.col + 1
      });
      for (let rowOffset = 0; rowOffset < merge.rowspan; rowOffset += 1) {
        for (let colOffset = 0; colOffset < merge.colspan; colOffset += 1) {
          if (rowOffset === 0 && colOffset === 0) {
            continue;
          }
          const coveredKey = displayCellKey(
            merge.row + rowOffset,
            merge.col + colOffset + 1
          );
          virtualState.mergeCoveredMap.set(coveredKey, true);
        }
      }
    });
  };
  const applySheetStructure = (ws) => {
    const structure = ws.structure;
    const mergeList = structure?.merge;
    if (mergeList) {
      setSheetMerges(mergeList);
    } else {
      const meta = ws.meta;
      if (meta && !virtualState.mergeStartMap.size) {
        setSheetMerges((ws.merge || []).map((merge) => ({
          ...merge,
          row: merge.row + meta.startRow
        })));
      }
    }
    applyStructureRowHeights(structure?.rowHeights);
    if (structure?.images) {
      sheetImages = structure.images;
      const sheetId = getActiveSheetId();
      if (sheetId !== void 0) {
        sheetImageCache.set(sheetId, structure.images);
      }
    }
    if (structure?.charts) {
      sheetCharts = structure.charts;
      const sheetId = getActiveSheetId();
      if (sheetId !== void 0) {
        sheetChartCache.set(sheetId, structure.charts);
      }
    }
  };
  const applyVirtualWindow = (ws) => {
    const meta = ws.meta;
    if (!meta) {
      return;
    }
    const isFirstWindow = !hasInitialWindow;
    if (!virtualState.active) {
      initializeVirtualSheet(ws);
    }
    applySheetStructure(ws);
    applyWindowRows(ws);
    applyWindowCells(ws);
    applyDefaultInitialFit();
    virtualState.loadedWindows.add(meta.startRow);
    virtualState.loadingWindows.delete(meta.startRow);
    syncWindowStats();
    hasInitialWindow = true;
    const activeSheetId = getActiveSheetId();
    if (activeSheetId !== void 0) {
      sheetStateCache.set(activeSheetId, virtualState);
    }
    if (isFirstWindow) {
      renderTable(ensureTable(), true);
    } else {
      table?.draw();
    }
    loadingState = false;
    sheetInitializing = false;
    renderChrome();
    if (!hasNotifiedFirstPaint) {
      hasNotifiedFirstPaint = true;
      resolveInitialRender();
      context?.onProgressiveRender?.();
    }
    if (isFirstWindow) {
      scheduleStableFirstPaintRefresh();
    }
    flushPendingViewRestore();
    requestPendingSearchWindow();
    flushPendingSearchJump();
    const start = viewportRange.start || meta.startRow;
    const end = Math.max(viewportRange.end, meta.endRow - 1, meta.startRow);
    ensureViewportWindows(start, end);
  };
  const resetViewState = () => {
    errorMessage = "";
    totalRows = 0;
    totalCols = 0;
    sheetDefaults = { ...DEFAULT_SHEET_DEFAULTS };
    sheetImages = [];
    sheetCharts = [];
    virtualState = createEmptyVirtualState();
    hasInitialWindow = false;
    resetViewportTracking();
    syncWindowStats();
    syncImageViewport();
    if (!table) {
      return;
    }
    table.loadColumns([]);
    table.loadData([]);
    renderedRows = [];
    table.scrollTo(0, 0);
    table.draw();
  };
  const cacheCurrentSheetState = () => {
    const sheetId = getActiveSheetId();
    if (sheetId === void 0 || !virtualState.active) {
      return;
    }
    sheetStateCache.set(sheetId, virtualState);
  };
  const restoreCachedSheetState = (sheetId) => {
    const cached = sheetStateCache.get(sheetId);
    if (!cached) {
      return false;
    }
    cached.loadingWindows.clear();
    virtualState = cached;
    syncScaledRowHeights();
    errorMessage = "";
    totalRows = cached.totalRows;
    totalCols = cached.totalCols;
    sheetDefaults = cached.defaults;
    sheetImages = sheetImageCache.get(sheetId) || [];
    sheetCharts = sheetChartCache.get(sheetId) || [];
    hasInitialWindow = cached.loadedWindows.size > 0;
    sheetInitializing = !hasInitialWindow;
    syncWindowStats();
    queueMicrotask(() => {
      if (disposed) {
        return;
      }
      if (virtualState !== cached || sheetId !== getActiveSheetId()) {
        return;
      }
      renderTable(ensureTable());
      syncImageViewport();
      scheduleStableFirstPaintRefresh();
    });
    return true;
  };
  const startSheetSession = () => {
    const sheetId = getActiveSheetId();
    if (sheetId === void 0) {
      loadingState = false;
      sheetInitializing = false;
      renderChrome();
      return;
    }
    sheetSessionId += 1;
    if (restoreCachedSheetState(sheetId)) {
      loadingState = false;
      renderChrome();
      return;
    }
    sheetInitializing = true;
    resetViewState();
    requestWindow(0, false);
  };
  const getSearchRowTop = (rowIndex) => {
    let top = scalePx(HEADER_HEIGHT);
    for (let index = 0; index < rowIndex; index += 1) {
      const height = virtualState.rowHeightCache.get(index) ?? virtualState.defaults.rowHeight;
      top += scaleRowHeight(height);
    }
    return top;
  };
  function readSpreadsheetScroll() {
    const content = getSpreadsheetContentSize();
    const width = Math.max(tableHost.clientWidth, content.contentWidth * zoom);
    const height = Math.max(tableHost.clientHeight, content.contentHeight * zoom);
    const top = table?.ctx.scrollY || 0;
    const left = table?.ctx.scrollX || 0;
    return {
      top,
      left,
      width,
      height,
      clientWidth: tableHost.clientWidth,
      clientHeight: tableHost.clientHeight,
      topRatio: height > tableHost.clientHeight ? top / (height - tableHost.clientHeight) : 0,
      leftRatio: width > tableHost.clientWidth ? left / (width - tableHost.clientWidth) : 0
    };
  }
  function restoreSpreadsheetView(state, isCurrent) {
    if (!isCurrent()) return;
    const scale = Number(state.scale ?? state.zoom?.scale);
    if (Number.isFinite(scale) && scale > 0) setZoom(scale);
    if (state.spreadsheet?.range || !sheets.length) return;
    const nextSheet = state.spreadsheet?.sheetId ?? getActiveSheetId();
    if (nextSheet === getActiveSheetId() && !state.scroll) return;
    return new Promise((resolve) => {
      pendingViewRestore = { state, sheetId: nextSheet, isCurrent, resolve };
      if (nextSheet !== getActiveSheetId()) {
        cacheCurrentSheetState();
        sheetIndex = nextSheet;
        renderChrome();
        startSheetSession();
        scrollActiveSheetIntoView();
      }
      flushPendingViewRestore();
    });
  }
  function flushPendingViewRestore() {
    const restore = pendingViewRestore;
    if (!restore || !table || !virtualState.active || restore.sheetId !== getActiveSheetId()) return;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (pendingViewRestore !== restore || !restore.isCurrent() || !table || disposed) return;
      const scroll = restore.state.scroll;
      const current = readSpreadsheetScroll();
      const coordinate = (value, ratio, maximum) => Number.isFinite(value) ? Number(value) : Number.isFinite(ratio) ? Number(ratio) * maximum : 0;
      const left = coordinate(scroll?.left, scroll?.leftRatio, Math.max(0, current.width - current.clientWidth));
      const top = coordinate(scroll?.top, scroll?.topRatio, Math.max(0, current.height - current.clientHeight));
      table.scrollTo(Math.max(0, left), Math.max(0, top));
      table.draw();
      syncImageViewport();
      scheduleViewportLoad();
      requestAnimationFrame(() => {
        if (pendingViewRestore !== restore || !restore.isCurrent()) return;
        pendingViewRestore = null;
        restore.resolve();
      });
    }));
  }
  function flushPendingSearchJump() {
    const pending = pendingSearchJump;
    if (!pending || pending.sheetId !== getActiveSheetId() || !virtualState.loadedWindows.has(getWindowStart(pending.row, virtualState.totalRows)) || !table) {
      return;
    }
    requestAnimationFrame(() => {
      if (disposed || !table || pendingSearchJump !== pending || pending.sheetId !== getActiveSheetId()) {
        return;
      }
      pendingSearchJump = null;
      const navigatingRange = rangeNavigation.isPending();
      const finishRange = rangeNavigation.prepare(virtualState.totalRows, virtualState.totalCols);
      if (navigatingRange && !finishRange) return;
      const targetTop = Math.max(
        0,
        getSearchRowTop(pending.row) - Math.max(0, (tableHost.clientHeight || 0) * 0.35)
      );
      const columnLeft = getSearchColumnLeft(
        getDisplayColumns(virtualState.columns, zoom),
        virtualState.dataKeys[pending.col] || getDataKey(pending.col)
      );
      const targetLeft = columnLeft === void 0 ? table.ctx.scrollX || 0 : Math.max(0, columnLeft - tableHost.clientWidth / 2);
      table.scrollTo(targetLeft, targetTop);
      table.draw();
      syncImageViewport();
      scheduleViewportLoad();
      if (finishRange) requestAnimationFrame(finishRange);
    });
  }
  function requestPendingSearchWindow() {
    const pending = pendingSearchJump;
    if (!pending || pending.sheetId !== getActiveSheetId() || !virtualState.totalRows) {
      return;
    }
    const windowStart = getWindowStart(pending.row, virtualState.totalRows);
    if (virtualState.loadedWindows.has(windowStart)) {
      flushPendingSearchJump();
      return;
    }
    requestWindow(windowStart, false);
  }
  function jumpToSpreadsheetSearchMatch(match) {
    const spreadsheet = match?.anchor?.spreadsheet;
    jumpToSpreadsheetCell(spreadsheet || null);
  }
  function jumpToSpreadsheetCell(spreadsheet) {
    pendingSearchJump = spreadsheet;
    if (!spreadsheet) {
      return;
    }
    if (spreadsheet.sheetId !== getActiveSheetId()) {
      cacheCurrentSheetState();
      sheetIndex = spreadsheet.sheetId;
      renderChrome();
      startSheetSession();
      scrollActiveSheetIntoView();
      const view = getTargetWindow(target);
      view?.queueMicrotask?.(requestPendingSearchWindow);
      return;
    }
    requestPendingSearchWindow();
  }
  function handleSheet(index) {
    latestSearchRequest += 1;
    rangeNavigation.cancel();
    if (sheetIndex === index) {
      scrollActiveSheetIntoView();
      return;
    }
    cacheCurrentSheetState();
    sheetIndex = index;
    renderChrome();
    startSheetSession();
    scrollActiveSheetIntoView();
  }
  controller.onWorkerEvent("searchWorkbook", ({ requestId, matches }) => {
    if (typeof requestId !== "number") {
      return;
    }
    const pending = pendingSearchRequests.get(requestId);
    if (!pending) {
      return;
    }
    pendingSearchRequests.delete(requestId);
    pending.resolve(Array.isArray(matches) ? matches : []);
  });
  const searchProvider = {
    async search(query, options = {}) {
      rangeNavigation.cancel();
      const normalizedQuery = query.replace(/\s+/g, " ").trim();
      searchOptions = options;
      const requestNumber = ++latestSearchRequest;
      if (!normalizedQuery) {
        pendingSearchJump = null;
        return setSearchState("", []);
      }
      await workbookReady;
      if (requestNumber !== latestSearchRequest || disposed || errorMessage) return searchState;
      const matches = await requestWorkbookSearch(normalizedQuery, searchOptions);
      if (requestNumber !== latestSearchRequest || disposed) {
        return searchState;
      }
      const nextMatches = matches.map((match, index) => ({
        id: `spreadsheet-search-${match.sheet}-${match.row}-${match.col}-${index}`,
        index,
        text: match.matchText,
        anchor: createSpreadsheetSearchAnchor(match, index),
        line: match.row + 1
      }));
      const nextState = setSearchState(normalizedQuery, nextMatches);
      jumpToSpreadsheetSearchMatch(nextState.current);
      return nextState;
    },
    next() {
      latestSearchRequest += 1;
      rangeNavigation.cancel();
      if (!searchMatches.length) {
        return searchState;
      }
      const nextState = setSearchState(
        searchState.query,
        searchMatches,
        searchState.currentIndex + 1
      );
      jumpToSpreadsheetSearchMatch(nextState.current);
      return nextState;
    },
    previous() {
      latestSearchRequest += 1;
      rangeNavigation.cancel();
      if (!searchMatches.length) {
        return searchState;
      }
      const nextState = setSearchState(
        searchState.query,
        searchMatches,
        searchState.currentIndex - 1
      );
      jumpToSpreadsheetSearchMatch(nextState.current);
      return nextState;
    },
    clear() {
      rangeNavigation.cancel();
      latestSearchRequest += 1;
      pendingSearchJump = null;
      return setSearchState("", []);
    },
    getState() {
      return searchState;
    }
  };
  registerFileViewerSearchProvider(root, searchProvider);
  registerFileViewerViewStateProvider(root, rangeNavigation.provider);
  const unsubscribeViewStateZoom = zoomEmitter.subscribe(() => {
    rangeNavigation.notify("zoom-change", "viewer");
  });
  const emitParseWorkbook = () => {
    emitWorker("parseWorkbook", {
      workbook: buffer,
      fileType: type,
      filename: context?.filename,
      textEncoding: context?.options?.spreadsheet?.textEncoding,
      includeEmptySheets: fillViewport
    });
  };
  controller.onWorkerEvent("sheets", ({ sheets: list }) => {
    sheets = list;
    resolveWorkbookReady?.();
    resolveWorkbookReady = null;
    const firstSheet = list.find((sheet) => !sheet.hidden) || list[0];
    if (firstSheet) {
      sheetIndex = firstSheet.id;
      renderChrome();
      startSheetSession();
      scrollActiveSheetIntoView();
      return;
    }
    sheetInitializing = false;
    loadingState = false;
    renderChrome();
    resolveInitialRender();
  });
  controller.onWorkerEvent("parseSheet", ({ sessionId, sheet, sheetData: ws }) => {
    if (sessionId !== sheetSessionId || sheet !== getActiveSheetId()) {
      return;
    }
    applyVirtualWindow(ws);
  });
  controller.onWorkerEvent("parseError", ({ sessionId, startRow, message }) => {
    resolveWorkbookReady?.();
    resolveWorkbookReady = null;
    if (sessionId && sessionId !== sheetSessionId) {
      return;
    }
    rangeNavigation.cancel("failed");
    sheetInitializing = false;
    loadingState = false;
    if (typeof startRow === "number") {
      virtualState.loadingWindows.delete(startRow);
      syncWindowStats();
      if (virtualState.active) {
        markWindowState(virtualState.rows, virtualState.totalRows, startRow, RowState.Placeholder);
        table?.draw();
      }
    } else {
      virtualState.loadingWindows.clear();
      syncWindowStats();
    }
    errorMessage = message || t("spreadsheet.error.parseFailed");
    renderChrome();
    rejectInitialRender(new Error(errorMessage));
  });
  controller.onWorkerError((event) => {
    rangeNavigation.cancel("failed");
    resolveWorkbookReady?.();
    resolveWorkbookReady = null;
    sheetInitializing = false;
    loadingState = false;
    errorMessage = event.message || t("spreadsheet.error.workerFailed");
    renderChrome();
    rejectInitialRender(new Error(errorMessage));
  });
  context?.registerExportAdapter?.({
    print: false,
    exportHtml: false
  });
  context?.registerThumbnailAdapter?.({
    beforeCapture: async ({ signal }) => {
      while (!hasInitialWindow && !errorMessage && !disposed) {
        if (signal?.aborted) {
          throw signal.reason;
        }
        await new Promise((resolve) => {
          const view = getTargetWindow(target);
          if (view) view.setTimeout(resolve, 16);
          else setTimeout(resolve, 16);
        });
      }
      if (errorMessage) {
        throw new Error(errorMessage);
      }
    },
    getTarget: () => tableWrapper
  });
  const abort = () => {
    rejectInitialRender(context?.signal?.reason || new DOMException("Spreadsheet rendering was aborted.", "AbortError"));
    instance.unmount();
  };
  const instance = {
    $el: root,
    unmount() {
      if (disposed) return;
      disposed = true;
      context?.signal?.removeEventListener("abort", abort);
      rangeNavigation.cancel("disposed");
      unsubscribeViewStateZoom();
      unregisterFileViewerViewStateProvider(root);
      imageSourceResolver.dispose();
      closeImageLightbox();
      tableHostShell.removeEventListener("dblclick", handleImageDoubleClick, true);
      imageLightbox.removeEventListener("click", handleImageLightboxClick);
      lightboxCloseButton.removeEventListener("click", closeImageLightbox);
      documentRef.removeEventListener("keydown", handleImageLightboxKeyDown);
      if (resizeFrame) {
        cancelAnimationFrame(resizeFrame);
      }
      if (scrollFrame) {
        cancelAnimationFrame(scrollFrame);
      }
      clearScheduledLayoutRefresh();
      resizeObserver?.disconnect();
      resizeObserver = null;
      pendingSearchJump = null;
      pendingSearchRequests.forEach(({ reject }) => {
        reject(new Error("Spreadsheet renderer was unmounted before search completed."));
      });
      pendingSearchRequests.clear();
      resolveWorkbookReady?.();
      resolveWorkbookReady = null;
      unregisterFileViewerSearchProvider(root);
      unregisterFileViewerZoomProvider(root);
      controller.destroy();
      table?.destroy();
      table = null;
      context?.registerExportAdapter?.(null);
      context?.registerThumbnailAdapter?.(null);
      if (root.parentNode === target) target.replaceChildren();
    }
  };
  context?.signal?.addEventListener("abort", abort, { once: true });
  try {
    if (context?.signal?.aborted) abort();
    if (disposed) throw context?.signal?.reason || new DOMException("Spreadsheet rendering was aborted.", "AbortError");
    ensureTable();
    const ResizeObserverCtor = getTargetWindow(target)?.ResizeObserver || (typeof ResizeObserver !== "undefined" ? ResizeObserver : void 0);
    if (ResizeObserverCtor) {
      resizeObserver = new ResizeObserverCtor(() => {
        if (resizeFrame) {
          cancelAnimationFrame(resizeFrame);
        }
        resizeFrame = requestAnimationFrame(() => {
          resizeFrame = 0;
          syncTableLayout();
        });
      });
      resizeObserver.observe(tableHost);
    }
    renderChrome();
    emitParseWorkbook();
    await initialRender;
    return instance;
  } catch (error2) {
    instance.unmount();
    void initialRender.catch(() => {
    });
    throw error2;
  }
};
var spreadsheet_default = renderFileViewerSpreadsheet;

// packages/renderers/spreadsheet/src/entry.ts
async function renderSpreadsheet(buffer, target, context) {
  assertSpreadsheetInput(buffer);
  if (context?.signal?.aborted) throw new DOMException("Spreadsheet rendering was aborted.", "AbortError");
  if (!target?.ownerDocument?.defaultView?.Worker && typeof Worker === "undefined") {
    throw new Error("Spreadsheet preview requires a parsing worker.");
  }
  const type = context?.filename?.split(".").pop()?.toLowerCase() || "xls";
  const controller = new AbortController();
  const abort = () => controller.abort(context?.signal?.reason || new DOMException("Spreadsheet rendering was aborted.", "AbortError"));
  context?.signal?.addEventListener("abort", abort, { once: true });
  const timeout = setTimeout(() => controller.abort(new Error("Spreadsheet preview exceeded the 30-second rendering limit.")), SPREADSHEET_LIMITS.workerTimeoutMs);
  let mounted = false;
  try {
    const instance = await spreadsheet_default(buffer, target, type, {
      ...context,
      signal: controller.signal,
      options: {
        ...context?.options,
        spreadsheet: {
          ...context?.options?.spreadsheet,
          worker: true,
          workerUrl: new URL("./sheet.worker.js", import.meta.url).href
        }
      }
    });
    if (controller.signal.aborted) {
      instance.unmount();
      throw controller.signal.reason;
    }
    mounted = true;
    const unmount = instance.unmount.bind(instance);
    let closed = false;
    return { ...instance, unmount: () => {
      if (closed) return;
      closed = true;
      context?.signal?.removeEventListener("abort", abort);
      unmount();
    } };
  } catch (error) {
    if (controller.signal.aborted) throw controller.signal.reason;
    throw error;
  } finally {
    clearTimeout(timeout);
    if (!mounted) context?.signal?.removeEventListener("abort", abort);
  }
}
var entry_default = renderSpreadsheet;
export {
  entry_default as default,
  renderSpreadsheet
};
