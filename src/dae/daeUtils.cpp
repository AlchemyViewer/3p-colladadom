/*
* Copyright 2006 Sony Computer Entertainment Inc.
*
* Licensed under the MIT Open Source License, for details please see license.txt or the website
* http://www.opensource.org/licenses/mit-license.php
*
*/ 
#include <cstdarg>
#include <algorithm>
#include <iterator>
#include <dae/daeUtils.h>
#include <dae/daeURI.h>

#ifdef _WIN32
#include <direct.h>  // for getcwd (windows)
#else
#include <unistd.h>  // for getcwd (linux)
#endif

#ifndef NO_BOOST
#include <boost/filesystem.hpp> // THIS WAS NOT COMMENTED.
#endif

#include <cstdio> // for tmpnam

using namespace std;

cdom::systemType cdom::getSystemType() {
#ifdef WIN32
	return Windows;
#else
	return Posix;
#endif
}

string cdom::replace(const string& s, const string& replace, const string& replaceWith) {
	if (replace.empty())
		return s;

	string result;
	size_t pos1 = 0, pos2 = s.find(replace);
	while (pos2 != string::npos) {
		result += s.substr(pos1, pos2-pos1);
		result += replaceWith;
		pos1 = pos2 + replace.length();
		pos2 = s.find(replace, pos1);
	}

	result += s.substr(pos1, s.length()-pos1);
	return result;
}

void cdom::trimWhitespaces(string& str) {
    string whitespaces ( " \t\f\v\n\r" );

    size_t found = str.find_last_not_of( whitespaces );
    if ( found != std::string::npos )
    {
        str.erase( found + 1 );
        found = str.find_first_not_of( whitespaces );
        if ( found != std::string::npos )
            str.erase( 0, found );
    }
    else
    {
        // whitespaces only
        str.clear();
    }
}

void cdom::tokenize(const string& s,
                    const string& separators,
                    /* out */ list<string>& tokens,
                    bool separatorsInResult) {
	size_t currentIndex = 0, nextTokenIndex = 0;
	while (currentIndex < s.length() &&
	       (nextTokenIndex = s.find_first_of(separators, currentIndex)) != string::npos) {
		if ((nextTokenIndex - currentIndex) > 0)
			tokens.push_back(s.substr(currentIndex, nextTokenIndex-currentIndex));
		if (separatorsInResult)
			tokens.push_back(string(1, s[nextTokenIndex]));
		currentIndex = nextTokenIndex+1;
	}

	if (currentIndex < s.length())
		tokens.push_back(s.substr(currentIndex, s.length()-currentIndex));
}

list<string> cdom::tokenize(const string& s,
                            const string& separators,
                            bool separatorsInResult) {
	list<string> result;
	tokenize(s, separators, result, separatorsInResult);
	return result;
}

#if 0
vector<string> cdom::makeStringArray(const char* s, ...) {
	va_list args;
	va_start(args, s);
	vector<string> result;
	while (s) {
		result.push_back(s);
		s = va_arg(args, const char*);
	}
	va_end(args);
	return result;
}

list<string> cdom::makeStringList(const char* s, ...) {
	va_list args;
	va_start(args, s);
	list<string> result;
	while (s) {
		result.push_back(s);
		s = va_arg(args, const char*);
	}
	va_end(args);
	return result;
}
#endif

string cdom::getCurrentDir() {
#ifdef __CELLOS_LV2__
	// The PS3 has no getcwd call.
	// !!!steveT Should we return app_home instead?
	return "/";
#else
	char buffer[1024];
#ifdef _WIN32
	_getcwd(buffer, 1024);
#else
	getcwd(buffer, 1024);
#endif
	return buffer;
#endif
}

string cdom::getCurrentDirAsUri() {
	string result = string("file://") + cdom::nativePathToUri(getCurrentDir());
	// Make sure the last char is a /
	if (!result.empty()  &&  result[result.length()-1] != '/')
		result += "/";
	return result;
}

char cdom::getFileSeparator() {
    if (getSystemType() == Windows) {
        return '\\';
    }
    return '/';
}
#ifndef NO_BOOST
const string& cdom::getSystemTmpDir() {
#ifndef NO_BOOST
	static string tmpDir = boost::filesystem::temp_directory_path().string();
#else
#ifdef WIN32
    static string tmpDir = string(getenv("TMP")) + getFileSeparator();
#elif defined(__linux__) || defined(__linux)
    static string tmpDir = "/tmp/";
#elif defined __APPLE_CC__
static string tmpDir = string(getenv("TMPDIR"));
#elif defined __CELLOS_LV2__
#error tmp dir for your system unknown
#else
#error tmp dir for your system unknown
#endif
#endif
    return tmpDir;
}

string cdom::getRandomFileName() {
#ifndef NO_BOOST
	return boost::filesystem::unique_path().string();
#else

    std::string randomSegment;
    // have to createa a buffer in order to make it multi-thread safe
    std::string tmpbuffer; tmpbuffer.resize(L_tmpnam*2+1);
    std::string tmp(tmpnam(&tmpbuffer[0]));
#ifdef WIN32
    randomSegment = tmp.substr(tmp.find_last_of('\\')+1);
#elif defined(__linux__) || defined(__linux)
    randomSegment = tmp.substr(tmp.find_last_of('/')+1);
#elif defined __APPLE_CC__
	randomSegment = tmp.substr(tmp.find_last_of('/')+1);
#elif defined __CELLOS_LV2__
#error  usage of tmpnam() for your system unknown
#else
#error  usage of tmpnam() for your system unknown
#endif
    return randomSegment;
#endif
}

const string& cdom::getSafeTmpDir() {
    // there is a race condition here is multiple collada-dom -enabled processes call getSafeTmpDir at the same time.
    // Therefore, have to check if directory already exists before using it. This still leaves the race
    // condition, but makes it more difficult to reproduce. A better alternative would be to stop relying on tmpnam!
    static string tmpDir;
    do {
        tmpDir = getSystemTmpDir() + getRandomFileName() + getFileSeparator();
    } while(boost::filesystem::is_directory(tmpDir));
    return tmpDir;
}
#endif //NO_BOOST

int cdom::strcasecmp(const char* str1, const char* str2) {
#ifdef _MSC_VER
	return _stricmp(str1, str2);
#else
	return ::strcasecmp(str1, str2);
#endif
}

string cdom::tolower(const string& s) {
	string result;
	transform(s.begin(), s.end(), back_inserter(result), ::tolower);
	return result;
}
