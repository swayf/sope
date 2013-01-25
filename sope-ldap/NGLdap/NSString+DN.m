/*
  Copyright (C) 2000-2007 SKYRIX Software AG
  Copyright (C) 2007      Helge Hess

  This file is part of SOPE.

  SOPE is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  SOPE is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with SOPE; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#import <Foundation/NSCharacterSet.h>

#define LDAP_DEPRECATED 1
#include <ldap.h>

#include "NSString+DN.h"
#include <NGExtensions/NSString+Ext.h>
#include "common.h"

static NSString *dnSeparator = @",";

static NSCharacterSet *escapableChars = nil;

static NSArray *cleanDNComponents(NSArray *_components) {
  unsigned i, count;
  id *cs;
  
  if ((count = [_components count]) == 0)
    return nil;
  
  cs = calloc(count, sizeof(id));
  
  for (i = 0; i < count; i++)
    cs[i] = [[_components objectAtIndex:i] stringByTrimmingWhiteSpaces];
  
  _components = [NSArray arrayWithObjects:cs count:count];
  if (cs != NULL) { free(cs); cs = NULL; }
  
  return _components;
}

static NSArray *explodeDN(const char *dn) {
  NSMutableArray *array;
  char **exploded;
  unsigned i;
  id *cs;

  if (dn == NULL)
    return nil;

  if (dn[0] == '\0') {
    return [NSArray arrayWithObjects: @"", nil];
  }

  exploded = ldap_explode_dn(dn, 0);
  if (exploded == NULL)
    return nil;

  /* Count number of RDNs */
  for (i = 0; exploded[i] != NULL; i++);

  cs = calloc(i, sizeof(id));

  array = [NSMutableArray arrayWithCapacity: i];
  for (i = 0; exploded[i] != NULL; i++) {
    [array addObject: [NSString stringWithCString: exploded[i]]];
  }

  ldap_value_free(exploded);

  if (cs != NULL) { free(cs); cs = NULL; }

  return cleanDNComponents(array);
}

@implementation NSString(DNSupport)

+ (NSString *)dnWithComponents:(NSArray *)_components {
  return [cleanDNComponents(_components) componentsJoinedByString:dnSeparator];
}

- (NSArray *)dnComponents {
  return explodeDN([self cString]);
}

- (NSString *)stringByAppendingDNComponent:(NSString *)_component {
  NSString *s;

  if (![(s = [self stringByTrimmingWhiteSpaces]) isNotEmpty])
    return _component;
  
  s = [dnSeparator stringByAppendingString:self];
  return [_component stringByAppendingString:s];
}

- (NSString *)stringByDeletingLastDNComponent {
  NSRange r;
  
  r = [self rangeOfString:dnSeparator];
  if (r.length == 0) return nil;
  
  return [[self substringFromIndex:(r.location + r.length)]
                stringByTrimmingWhiteSpaces];
}

- (NSString *)lastDNComponent {
  NSRange r;
  
  r = [self rangeOfString:dnSeparator];
  if (r.length == 0) return nil;
  
  return [[self substringToIndex:r.location] stringByTrimmingWhiteSpaces];
}

- (const char *)ldapRepresentation {
  return [self UTF8String];
}

- (NSDate *)ldapTimestamp {
  /* eg: '20000403055250Z' */
  unsigned   len;
  short      year, month, day, hour, minute, second;
  NSString   *tzname;
  NSTimeZone *tz;
  
  if ((len = [self length]) == 0)
    return nil;

  if (len < 14)
    return nil;
  
  year   = [[self substringWithRange:NSMakeRange(0,  4)] intValue];
  month  = [[self substringWithRange:NSMakeRange(4,  2)] intValue];
  day    = [[self substringWithRange:NSMakeRange(6,  2)] intValue];
  hour   = [[self substringWithRange:NSMakeRange(8,  2)] intValue];
  minute = [[self substringWithRange:NSMakeRange(10, 2)] intValue];
  second = [[self substringWithRange:NSMakeRange(12, 2)] intValue];

  /* timezone ??? */
  tzname = @"GMT";
  tz = [NSTimeZone timeZoneWithAbbreviation:tzname];

  return [NSCalendarDate dateWithYear:year month:month
                         day:day hour:hour minute:minute second:second
                         timeZone:tz];
}

- (NSString *) escapedForLDAPDN
{
  NSMutableString *newString;
  NSString *format;
  unichar *uniString;
  unichar currentChar;
  NSUInteger count, length;

  if (!escapableChars)
    {
      escapableChars = [NSCharacterSet
                         characterSetWithCharactersInString: @"\"+,;<>\\"];
      [escapableChars retain];
    }

  length = [self length];
  newString = [NSMutableString stringWithCapacity: length];

  uniString = NSZoneMalloc (NULL, sizeof (unichar) * length);
  [self getCharacters: uniString];

  /* see rfc4514, section 2.4 */
  for (count = 0; count < length; count++)
    {
      currentChar = uniString[count];
      if ((currentChar == ' ' && (count == 0 || count == (length - 1)))
          || [escapableChars characterIsMember: currentChar])
        format = @"\\%Lc";
      else
        format = @"%Lc";
      [newString appendFormat: format, currentChar];
    }

  NSZoneFree (NULL, uniString);

  return newString;
}

@end /* NSString(DNSupport) */
