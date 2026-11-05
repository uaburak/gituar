import { test } from "node:test";
import assert from "node:assert/strict";
import { isChordLine, parse, prefersFlats, semitoneOffset, transpose, rootNote } from "../src/chords.ts";
import { slugify, turkeyNormalized, searchSongs } from "../src/turkish.ts";

test("akor satırı tespiti", () => {
  assert.equal(isChordLine("Dm     Am     Bb"), true);
  assert.equal(isChordLine("Dokunsalar ağlayacaksın"), false);
  assert.equal(isChordLine("e|---0---|"), false);
  assert.equal(isChordLine("Intro: Dm Am"), true);
  assert.equal(isChordLine("Am - Dm | G (x2)"), true);
});

test("transpoze hizayı korur", () => {
  assert.equal(transpose("Dm     Am     Bb", 2), "Em     Bm     C");
  assert.equal(transpose("C#m7 D/F#", 1, false), "Dm7  D#/G"); // akor kısalınca hiza için boşluk eklenir
  assert.equal(transpose("Nakarat: x2", 3), "Nakarat: x2");
  assert.equal(transpose("G  C", 1, true), "Ab Db"); // akor uzayınca sonraki sütun korunur
});

test("ton farkı ve bemol tercihi", () => {
  assert.equal(semitoneOffset("Dm", "E"), 2);
  assert.equal(semitoneOffset("C", "B"), -1);
  assert.equal(prefersFlats("F", "C"), true);
  assert.equal(prefersFlats("G", "Dm"), true);
  assert.equal(prefersFlats("E", "C"), false);
  assert.equal(rootNote("C#m"), "C#");
});

test("parse satır sayısı", () => {
  assert.equal(parse("a\r\nb\nc").length, 3);
});

test("türkçe normalize ve slug", () => {
  assert.equal(turkeyNormalized("Barış MANÇO İçin"), "baris manco icin");
  assert.equal(slugify("Barış Manço"), "baris-manco");
  assert.equal(slugify("Dolu Kadehi Ters Tut"), "dolu-kadehi-ters-tut");
  assert.equal(slugify("Anason (Akustik)"), "anason-akustik");
});

test("çok kelimeli arama", () => {
  const songs = [
    { songName: "Gülümse", artist: "Sezen Aksu" },
    { songName: "Anason", artist: "Zakkum" },
  ];
  assert.deepEqual(searchSongs(songs, "sezen gülümse").map((s) => s.songName), ["Gülümse"]);
  assert.deepEqual(searchSongs(songs, "zak").map((s) => s.songName), ["Anason"]);
});
