/*
* Copyright 2006 Sony Computer Entertainment Inc.
*
* Licensed under the MIT Open Source License, for details please see license.txt or the website
* http://www.opensource.org/licenses/mit-license.php
*
*/ 

#ifndef __DAE_PLATFORM_H__
#define __DAE_PLATFORM_H__

#if defined(WIN32)
#include <dae/daeWin32Platform.h>
#elif defined(__clang__)
#include <dae/daeClangPlatform.h>
#elif defined(__GCC__)
#include <dae/daeGCCPlatform.h>
#else
// Use some generic settings
#include <limits.h>

#define PLATFORM_INT8	char
#define PLATFORM_INT16	short
#define PLATFORM_INT32	int
#define PLATFORM_INT64	long long
#define PLATFORM_UINT8	unsigned char
#define PLATFORM_UINT16 unsigned short
#define PLATFORM_UINT32 unsigned int
#define PLATFORM_UINT64 unsigned long long
#define PLATFORM_FLOAT32 float
#define PLATFORM_FLOAT64 double

#define DLLSPEC
#endif

#endif
