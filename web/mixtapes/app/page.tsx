'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
// Signed private images must load directly, never through an optimizing/cache proxy.
/* oxlint-disable next/no-img-element */
type Track = { id: string; track_name: string | null; artist: string | null; track_uri: string | null; note: string | null; note_image_url: string | null };
type Tape = { title: string | null; description: string | null; cover_url: string | null; tracks: Track[] };
export default function Home() {
  const [tape, setTape] = useState<Tape | null>(null);
  const [token, setToken] = useState('');
  const [message, setMessage] = useState('Open the mixtape link someone shared with you.');
  useEffect(() => {
    const controller = new AbortController();
    const key = window.location.hash.slice(1);
    if (!/^[0-9a-f]{64}$/.test(key)) return;
    fetch('https://ghmuafydukliccwamkrq.supabase.co/functions/v1/shared-mixtape', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: key }), signal: controller.signal, cache: 'no-store',
    }).then(async response => {
      if (!response.ok) throw new Error(response.status === 404 ? 'This link is no longer available.' : 'Couldn’t load this mixtape. Please try again.');
      setTape(await response.json());
      setToken(key);
    }).catch(error => { if (!controller.signal.aborted) { setToken(key); setMessage(error.message); } });
    return () => controller.abort();
  }, []);
  return <main>
    <header><Link href="/" className="brand">Heartable</Link><span>a mixtape for you</span></header>
    {tape ? <>
      <section className="dedication">
        {tape.cover_url && <img className="cover" src={tape.cover_url} alt="Mixtape cover" referrerPolicy="no-referrer" />}
        <div><p className="eyebrow">{tape.tracks.length} songs, chosen for you</p>
          <h1>{tape.title || 'Your mixtape'}</h1>
          {tape.description && <p className="description">{tape.description}</p>}
          <a className="open" href={`heartable://mixtape?token=${token}`}>Open in Heartable <span aria-hidden="true">↗</span></a>
        </div>
      </section>
      <ol className="tracks">{tape.tracks.map((track, index) => <li key={track.id}>
        <span className="number">{String(index + 1).padStart(2, '0')}</span>
        <div className="track-content"><h2>{track.track_name || 'Untitled track'}</h2><p className="artist">{track.artist}</p>
          {track.note && <p className="note">{track.note}</p>}
          {track.note_image_url && <img className="photo" src={track.note_image_url} alt={`Accompanying ${track.track_name || 'this song'}`} referrerPolicy="no-referrer" />}
        </div>
      </li>)}</ol>
      <footer>Heartable is currently in private beta. Ask your friend for an app invite.<br />Anyone with this link can view this shared version.</footer>
    </> : <section className="empty"><h1>A little collection.<br />A lot of feeling.</h1><output>{message}</output>{token && <button onClick={() => window.location.reload()}>Try again</button>}</section>}
  </main>;
}
