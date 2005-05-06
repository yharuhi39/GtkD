/*
 *	 Copyright (C)	2003-2004 by Digital	Mars,	www.digitalmars.com
 *	 Written	by	Walter Bright
 *
 *	 This	software	is	provided	'as-is',	without any	express or implied
 *	 warranty. In no event will the authors be held	liable for any	damages
 *	 arising	from the	use of this	software.
 *
 *	 Permission	is	granted to anyone	to	use this	software	for any purpose,
 *	 including commercial applications,	and to alter it and redistribute	it
 *	 freely,	subject to the	following restrictions:
 *
 *	 o	 The origin	of	this software must not be misrepresented;	you must	not
 *		 claim that	you wrote the original software.	If	you use this software
 *		 in a	product,	an	acknowledgment	in	the product	documentation would be
 *		 appreciated but is not	required.
 *	 o	 Altered	source versions must	be	plainly marked	as	such,	and must	not
 *		 be misrepresented as being the original software.
 *	 o	 This	notice may not	be	removed or altered from	any source
 *		 distribution.
 */

/*
 *	This file is part	of	dool.
 *	
 *	License for	redistribution	is	by	either the Artistic License in artistic.txt,
 *	or	the LGPL
 */

/*
 *	adapted by Antonio Monteiro
 */



//	Description	of	UTF-8	at:
//	http://www.cl.cam.ac.uk/~mgk25/unicode.html#utf-8

module dool.util.Utf;

//debug=utf;		// uncomment to turn on debugging printf's

class	UtfError	: Error
{
	 size_t idx;	// index in string of where error occurred

	 this(char[] s, size_t i)
	 {
	idx = i;
	super(s);
	 }
}

class	Utf
{

	static bit isValidDchar(dchar c)
	{
	    /* Note: FFFE and FFFF are specifically permitted by the
		* Unicode standard for application internal use, but are	not
		* allowed for interchange.
		* (thanks to Arcane Jill)
		* However, we still mark them	as	invalid.
		*/
	
	    return c < 0xD800 ||
		(c > 0xDFFF && c <= 0x10FFFF && c != 0xFFFE && c != 0xFFFF);
	}
	
	unittest
	{
	    debug(utf) printf("utf.isValidDchar.unittest\n");
	    assert(isValidDchar(cast(dchar)'a') == true);
	    assert(isValidDchar(cast(dchar)0x1FFFFF) == false);
	}
	
	/* =================== Decode ======================= */
	
	static dchar decode(char[] s, inout size_t idx)
	    in
	    {
		assert(idx >= 0 && idx < s.length);
	    }
	    out (result)
	    {
		assert(isValidDchar(result));
	    }
	    body
	    {
		size_t len = s.length;
		dchar V;
		size_t i = idx;
		char u = s[i];
	
		if (u & 0x80)
		{   uint n;
		    char u2;
	
		    /* The following encodings are valid, except for the 5 and 6 byte
		     * combinations:
		     *	0xxxxxxx
		     *	110xxxxx 10xxxxxx
		     *	1110xxxx 10xxxxxx 10xxxxxx
		     *	11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
		     *	111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
		     *	1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
		     */
		    for (n = 1; ; n++)
		    {
			if (n > 4)
			    goto Lerr;		// only do the first 4 of 6 encodings
			if (((u << n) & 0x80) == 0)
			{
			    if (n == 1)
				goto Lerr;
			    break;
			}
		    }
	
		    // Pick off (7 - n) significant bits of B from first byte of octet
		    V = cast(dchar)(u & ((1 << (7 - n)) - 1));
	
		    if (i + (n - 1) >= len)
			goto Lerr;			// off end of string
	
		    /* The following combinations are overlong, and illegal:
		     *	1100000x (10xxxxxx)
		     *	11100000 100xxxxx (10xxxxxx)
		     *	11110000 1000xxxx (10xxxxxx 10xxxxxx)
		     *	11111000 10000xxx (10xxxxxx 10xxxxxx 10xxxxxx)
		     *	11111100 100000xx (10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx)
		     */
		    u2 = s[i + 1];
		    if ((u & 0xFE) == 0xC0 ||
			(u == 0xE0 && (u2 & 0xE0) == 0x80) ||
			(u == 0xF0 && (u2 & 0xF0) == 0x80) ||
			(u == 0xF8 && (u2 & 0xF8) == 0x80) ||
			(u == 0xFC && (u2 & 0xFC) == 0x80))
			goto Lerr;			// overlong combination
	
		    for (uint j = 1; j != n; j++)
		    {
			u = s[i + j];
			if ((u & 0xC0) != 0x80)
			    goto Lerr;			// trailing bytes are 10xxxxxx
			V = (V << 6) | (u & 0x3F);
		    }
		    if (!isValidDchar(V))
			goto Lerr;
		    i += n;
		}
		else
		{
		    V = cast(dchar) u;
		    i++;
		}
	
		idx = i;
		return V;
	
		 Lerr:
		throw new UtfError("invalid UTF-8 sequence", i);
	    }
	
	unittest
	{   size_t i;
	    dchar c;
	
	    debug(utf) printf("utf.decode.unittest\n");
	
	    static char[] s1 = "abcd";
	    i = 0;
	    c = decode(s1, i);
	    assert(c == cast(dchar)'a');
	    assert(i == 1);
	    c = decode(s1, i);
	    assert(c == cast(dchar)'b');
	    assert(i == 2);
	
	    static char[] s2 = "\xC2\xA9";
	    i = 0;
	    c = decode(s2, i);
	    assert(c == cast(dchar)'\u00A9');
	    assert(i == 2);
	
	    static char[] s3 = "\xE2\x89\xA0";
	    i = 0;
	    c = decode(s3, i);
	    assert(c == cast(dchar)'\u2260');
	    assert(i == 3);
	
	    static char[][] s4 =
	    [	"\xE2\x89",		// too short
		"\xC0\x8A",
		"\xE0\x80\x8A",
		"\xF0\x80\x80\x8A",
		"\xF8\x80\x80\x80\x8A",
		"\xFC\x80\x80\x80\x80\x8A",
	    ];
	
	    for (int j = 0; j < s4.length; j++)
	    {
		try
		{
		    i = 0;
		    c = decode(s4[j], i);
		    assert(0);
		}
		catch (UtfError u)
		{
		    i = 23;
		}
		assert(i == 23);
	    }
	}
	
	/********************************************************/
	
	static dchar decode(wchar[] s, inout size_t idx)
	    in
	    {
		assert(idx >= 0 && idx < s.length);
	    }
	    out (result)
	    {
		assert(isValidDchar(result));
	    }
	    body
	    {
		char[] msg;
		dchar V;
		size_t i = idx;
		uint u = s[i];
	
		if (u & ~0x7F)
		{   if (u >= 0xD800 && u <= 0xDBFF)
		    {   uint u2;
	
			if (i + 1 == s.length)
			{   msg = "surrogate UTF-16 high value past end of string";
			    goto Lerr;
			}
			u2 = s[i + 1];
			if (u2 < 0xDC00 || u2 > 0xDFFF)
			{   msg = "surrogate UTF-16 low value out of range";
			    goto Lerr;
			}
			u = ((u - 0xD7C0) << 10) + (u2 - 0xDC00);
			i += 2;
		    }
		    else if (u >= 0xDC00 && u <= 0xDFFF)
		    {   msg = "unpaired surrogate UTF-16 value";
			goto Lerr;
		    }
		    else if (u == 0xFFFE || u == 0xFFFF)
		    {   msg = "illegal UTF-16 value";
			goto Lerr;
		    }
		    else
			i++;
		}
		else
		{
		    i++;
		}
	
		idx = i;
		return cast(dchar)u;
	
		 Lerr:
		throw new UtfError(msg, i);
	    }
	
	/********************************************************/
	
	static dchar decode(dchar[] s, inout size_t idx)
	    in
	    {
		assert(idx >= 0 && idx < s.length);
	    }
	    body
	    {
		size_t i = idx;
		dchar c = s[i];
	
		if (!isValidDchar(c))
		    goto Lerr;
		idx = i + 1;
		return c;
	
		 Lerr:
		throw new UtfError("invalid UTF-32 value", i);
	    }
	
	
	/* =================== Encode ======================= */
	
	static void encode(inout char[] s, dchar c)
	    in
	    {
		assert(isValidDchar(c));
	    }
	    body
	    {
		char[] r = s;
	
		if (c <= 0x7F)
		{
		    r ~= cast(char) c;
		}
		else
		{
		    char[4] buf;
		    uint L;
	
		    if (c <= 0x7FF)
		    {
			buf[0] = cast(char)(0xC0 | (c >> 6));
			buf[1] = cast(char)(0x80 | (c & 0x3F));
			L = 2;
		    }
		    else if (c <= 0xFFFF)
		    {
			buf[0] = cast(char)(0xE0 | (c >> 12));
			buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
			buf[2] = cast(char)(0x80 | (c & 0x3F));
			L = 3;
		    }
		    else if (c <= 0x10FFFF)
		    {
			buf[0] = cast(char)(0xF0 | (c >> 18));
			buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
			buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
			buf[3] = cast(char)(0x80 | (c & 0x3F));
			L = 4;
		    }
		    else
		    {
			assert(0);
		    }
		    r ~= buf[0 .. L];
		}
		s = r;
	    }
	
	unittest
	{
	    debug(utf) printf("utf.encode.unittest\n");
	
	    char[] s = "abcd";
	    encode(s, cast(dchar)'a');
	    assert(s.length == 5);
	    assert(s == "abcda");
	
	    encode(s, cast(dchar)'\u00A9');
	    assert(s.length == 7);
	    assert(s == "abcda\xC2\xA9");
	    //assert(s == "abcda\u00A9");	// BUG: fix compiler
	
	    encode(s, cast(dchar)'\u2260');
	    assert(s.length == 10);
	    assert(s == "abcda\xC2\xA9\xE2\x89\xA0");
	}
	
	/********************************************************/
	
	static void encode(inout wchar[] s, dchar c)
	    in
	    {
		assert(isValidDchar(c));
	    }
	    body
	    {
		wchar[] r = s;
	
		if (c <= 0xFFFF)
		{
		    r ~= cast(wchar) c;
		}
		else
		{
		    wchar[2] buf;
	
		    buf[0] = (((c - 0x10000) >> 10) & 0x3FF) + 0xD800;
		    buf[1] = ((c - 0x10000) & 0x3FF) + 0xDC00;
		    r ~= buf;
		}
		s = r;
	    }
	
	static void encode(inout dchar[] s, dchar c)
	    in
	    {
		assert(isValidDchar(c));
	    }
	    body
	    {
		s ~= c;
	    }
	
	/* =================== Validation ======================= */
	
	static void validate(char[] s)
	{
	    size_t len = s.length;
	    size_t i;
	
	    for (i = 0; i < len; )
	    {
		decode(s, i);
	    }
	}
	
	static void validate(wchar[] s)
	{
	    size_t len = s.length;
	    size_t i;
	
	    for (i = 0; i < len; )
	    {
		decode(s, i);
	    }
	}
	
	static void validate(dchar[] s)
	{
	    size_t len = s.length;
	    size_t i;
	
	    for (i = 0; i < len; )
	    {
		decode(s, i);
	    }
	}
	
	/* =================== Conversion to UTF8 ======================= */
	
	static char[] toUTF8(char[4] buf, dchar c)
	    in
	    {
		assert(isValidDchar(c));
	    }
	    body
	    {
		if (c <= 0x7F)
		{
		    buf[0] = cast(char) c;
		    return buf[0 .. 1];
		}
		else if (c <= 0x7FF)
		{
		    buf[0] = cast(char)(0xC0 | (c >> 6));
		    buf[1] = cast(char)(0x80 | (c & 0x3F));
		    return buf[0 .. 2];
		}
		else if (c <= 0xFFFF)
		{
		    buf[0] = cast(char)(0xE0 | (c >> 12));
		    buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
		    buf[2] = cast(char)(0x80 | (c & 0x3F));
		    return buf[0 .. 3];
		}
		else if (c <= 0x10FFFF)
		{
		    buf[0] = cast(char)(0xF0 | (c >> 18));
		    buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
		    buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
		    buf[3] = cast(char)(0x80 | (c & 0x3F));
		    return buf[0 .. 4];
		}
		else
		{
		    assert(0);
		}
	    }
	
	static char[] toUTF8(char[] s)
	    in
	    {
		validate(s);
	    }
	    body
	    {
		return s;
	    }
	
	static char[] toUTF8(wchar[] s)
	{
	    char[] r;
	    size_t i;
	    size_t slen = s.length;
	
	    r.length = slen;
	
	    for (i = 0; i < slen; i++)
	    {	wchar c = s[i];
	
		if (c <= 0x7F)
		    r[i] = c;		// fast path for ascii
		else
		{
		    r.length = i;
		    foreach (dchar c; s[i .. slen])
		    {
			encode(r, c);
		    }
		    break;
		}
	    }
	    return r;
	}
	
	static char[] toUTF8(dchar[] s)
	{
	    char[] r;
	    size_t i;
	    size_t slen = s.length;
	
	    r.length = slen;
	
	    for (i = 0; i < slen; i++)
	    {	dchar c = s[i];
	
		if (c <= 0x7F)
		    r[i] = c;		// fast path for ascii
		else
		{
		    r.length = i;
		    foreach (dchar c; s[i .. slen])
		    {
			encode(r, c);
		    }
		    break;
		}
	    }
	    return r;
	}
	
	/* =================== Conversion to UTF16 ======================= */
	
	static wchar[] toUTF16(wchar[2] buf, dchar c)
	    in
	    {
		assert(isValidDchar(c));
	    }
	    body
	    {
		if (c <= 0xFFFF)
		{
		    buf[0] = cast(wchar) c;
		    return buf[0 .. 1];
		}
		else
		{
		    buf[0] = (((c - 0x10000) >> 10) & 0x3FF) + 0xD800;
		    buf[1] = ((c - 0x10000) & 0x3FF) + 0xDC00;
		    return buf[0 .. 2];
		}
	    }
	
	static wchar[] toUTF16(char[] s)
	{
	    wchar[] r;
	    size_t slen = s.length;
	
	    r.length = slen;
	    r.length = 0;
	    for (size_t i = 0; i < slen; )
	    {
		dchar c = s[i];
		if (c <= 0x7F)
		{
		    i++;
		    r ~= c;
		}
		else
		{
		    c = decode(s, i);
		    encode(r, c);
		}
	    }
	    return r;
	}
	
	static wchar* toUTF16z(char[] s)
	{
	    wchar[] r;
	    size_t slen = s.length;
	
	    r.length = slen + 1;
	    r.length = 0;
	    for (size_t i = 0; i < slen; )
	    {
		dchar c = s[i];
		if (c <= 0x7F)
		{
		    i++;
		    r ~= c;
		}
		else
		{
		    c = decode(s, i);
		    encode(r, c);
		}
	    }
	    r ~= "\000";
	    return r;
	}
	
	static wchar[] toUTF16(wchar[] s)
	    in
	    {
		validate(s);
	    }
	    body
	    {
		return s;
	    }
	
	static wchar[] toUTF16(dchar[] s)
	{
	    wchar[] r;
	    size_t slen = s.length;
	
	    r.length = slen;
	    r.length = 0;
	    for (size_t i = 0; i < slen; i++)
	    {
		encode(r, s[i]);
	    }
	    return r;
	}
	
	/* =================== Conversion to UTF32 ======================= */
	
	static dchar[] toUTF32(char[] s)
	{
	    dchar[] r;
	    size_t slen = s.length;
	    size_t j = 0;
	
	    r.length = slen;		// r[] will never be longer than s[]
	    for (size_t i = 0; i < slen; )
	    {
		dchar c = s[i];
		if (c >= 0x80)
		    c = decode(s, i);
		else
		    i++;		// c is ascii, no need for decode
		r[j++] = c;
	    }
	    return r[0 .. j];
	}
	
	static dchar[] toUTF32(wchar[] s)
	{
	    dchar[] r;
	    size_t slen = s.length;
	    size_t j = 0;
	
	    r.length = slen;		// r[] will never be longer than s[]
	    for (size_t i = 0; i < slen; )
	    {
		dchar c = s[i];
		if (c >= 0x80)
		    c = decode(s, i);
		else
		    i++;		// c is ascii, no need for decode
		r[j++] = c;
	    }
	    return r[0 .. j];
	}
	
	static dchar[] toUTF32(dchar[] s)
	    in
	    {
		validate(s);
	    }
	    body
	    {
		return s;
	    }
	
	/* ================================ tests ================================== */
	
	unittest
	{
	    debug(utf) printf("utf.toUTF.unittest\n");
	
	    char[] c;
	    wchar[] w;
	    dchar[] d;
	
	    c = "hello";
	    w = toUTF16(c);
	    assert(w == "hello");
	    d = toUTF32(c);
	    assert(d == "hello");
	
	    c = toUTF8(w);
	    assert(c == "hello");
	    d = toUTF32(w);
	    assert(d == "hello");
	
	    c = toUTF8(d);
	    assert(c == "hello");
	    w = toUTF16(d);
	    assert(w == "hello");
	
	
	    c = "hel\u1234o";
	    w = toUTF16(c);
	    assert(w == "hel\u1234o");
	    d = toUTF32(c);
	    assert(d == "hel\u1234o");
	
	    c = toUTF8(w);
	    assert(c == "hel\u1234o");
	    d = toUTF32(w);
	    assert(d == "hel\u1234o");
	
	    c = toUTF8(d);
	    assert(c == "hel\u1234o");
	    w = toUTF16(d);
	    assert(w == "hel\u1234o");
	
	
	    c = "he\U0010AAAAllo";
	    w = toUTF16(c);
	    //foreach (wchar c; w) printf("c = x%x\n", c);
	    //foreach (wchar c; cast(wchar[])"he\U0010AAAAllo") printf("c = x%x\n", c);
	    assert(w == "he\U0010AAAAllo");
	    d = toUTF32(c);
	    assert(d == "he\U0010AAAAllo");
	
	    c = toUTF8(w);
	    assert(c == "he\U0010AAAAllo");
	    d = toUTF32(w);
	    assert(d == "he\U0010AAAAllo");
	
	    c = toUTF8(d);
	    assert(c == "he\U0010AAAAllo");
	    w = toUTF16(d);
	    assert(w == "he\U0010AAAAllo");
	}
}