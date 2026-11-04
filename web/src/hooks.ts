import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from './api';

export interface Async<T> { data: T | null; error: ApiError | null; loading: boolean; reload: () => void }

/** Runs `fn` whenever `key` changes; a null key means "do not load yet". Older answers never overwrite newer ones. */
export function useAsync<T>(key: string | null, fn: () => Promise<T>): Async<T> {
  const [state, setState] = useState<{ data: T | null; error: ApiError | null; loading: boolean }>({ data: null, error: null, loading: key !== null });
  const [tick, setTick] = useState(0);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  useEffect(() => {
    if (key === null) { setState({ data: null, error: null, loading: false }); return; }
    let alive = true;
    setState((s) => ({ ...s, loading: true, error: null }));
    fnRef.current()
      .then((data) => { if (alive) setState({ data, error: null, loading: false }); })
      .catch((e) => { if (alive) setState({ data: null, error: e instanceof ApiError ? e : new ApiError(0, 'network', null), loading: false }); });
    return () => { alive = false; };
  }, [key, tick]);
  const reload = useCallback(() => setTick((n) => n + 1), []);
  return { ...state, reload };
}

export function useDebounced<T>(value: T, ms = 250): T {
  const [v, setV] = useState(value);
  useEffect(() => { const id = setTimeout(() => setV(value), ms); return () => clearTimeout(id); }, [value, ms]);
  return v;
}
