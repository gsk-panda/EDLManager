# Global Search Feature

## Overview

The EDL Manager now includes a global search feature that allows you to search across all entries in all EDLs from a single search interface.

## Features

### Search Capabilities
- **Search by value**: Find IP addresses, domains, or URLs
- **Search by comment**: Find entries by their comment text
- **Partial matching**: Searches use wildcards automatically (e.g., "192.168" finds all 192.168.x.x IPs)
- **Case-insensitive**: Search is not case-sensitive
- **Cross-EDL**: Searches across ALL EDLs simultaneously

### Search Results Display
- **EDL name and type**: Shows which EDL contains each entry
- **Entry value**: The actual IP/domain/URL
- **Comment**: Entry comment if present
- **Status indicators**:
  - **Active** (green): Entry is enabled and not expired
  - **Disabled** (gray): Entry is manually disabled
  - **Expired** (red): Entry has passed its expiration date
- **Expiration date**: Shows when entry will/did expire
- **Direct links**: Click "view" to jump directly to the entry in its EDL

### User Interface

#### Header Search Box
- Available on **every page** when logged in
- Located between the "EDL Manager" logo and user info
- Just type and press Enter to search

#### Dedicated Search Page
- Access via: `https://example.com/edl/search`
- Or use the header search box
- Shows full search interface with results table
- Displays result count (up to 500 results)

#### Entry Highlighting
- When you click "view" from search results, the page:
  1. Jumps directly to that entry in the EDL detail view
  2. Briefly highlights the entry row in yellow
  3. Uses smooth scrolling for better UX

## Usage Examples

### Example 1: Find All Entries from a Specific Subnet
**Search**: `10.0.1`

**Results**: All entries starting with `10.0.1` (10.0.1.1, 10.0.1.0/24, etc.)

### Example 2: Find Entries by Comment
**Search**: `scanner`

**Results**: All entries with "scanner" in their comment field

### Example 3: Find a Specific Domain
**Search**: `badsite.com`

**Results**: 
- `badsite.com`
- `*.badsite.com`
- `www.badsite.com/path`
- Any entry with "badsite.com" in value or comment

### Example 4: Find Wildcard Entries
**Search**: `*.`

**Results**: All wildcard domain entries

## Implementation Details

### Files Modified
1. **`src/routes/edls.js`**: Added `/search` route with search logic
2. **`views/search.ejs`**: New search results page template
3. **`views/partials/header.ejs`**: Added search box to header + CSS for highlighting
4. **`views/edl.ejs`**: Added `id` attributes to entry rows for direct linking

### Database Query
```sql
SELECT 
  en.id, en.value, en.comment, en.enabled, en.expires_at, en.created_at,
  e.id as edl_id, e.name as edl_name, e.slug, e.type, e.enabled as edl_enabled
FROM edl_entries en
JOIN edls e ON e.id = en.edl_id
WHERE en.value ILIKE $1 OR en.comment ILIKE $1
ORDER BY 
  en.enabled DESC,
  e.name,
  en.value
LIMIT 500
```

### Performance Considerations
- **Result limit**: 500 entries maximum to prevent slow queries
- **Index recommendation**: Consider adding indexes if you have many entries:
  ```sql
  CREATE INDEX idx_entries_value_trgm ON edl_entries USING gin (value gin_trgm_ops);
  CREATE INDEX idx_entries_comment_trgm ON edl_entries USING gin (comment gin_trgm_ops);
  ```
  (Requires `pg_trgm` extension for fuzzy text search)

## API Endpoint

### GET /search

**Parameters**:
- `q` (query string): Search term

**Example**:
```
GET /edl/search?q=192.168.1
```

**Response**: HTML page with search results

## Future Enhancements

Potential improvements for future versions:

1. **Advanced search options**:
   - Filter by EDL
   - Filter by type (IP/Domain/URL)
   - Filter by status (active/disabled/expired)
   - Date range filtering

2. **Search syntax**:
   - Exact match quotes: `"192.168.1.1"`
   - Exclude terms: `-scanner`
   - Boolean operators: `malware AND scanner`

3. **Export search results**:
   - Download matching entries as CSV or text
   - Bulk operations on search results

4. **Search history**:
   - Save recent searches
   - Saved search queries

5. **API endpoint**:
   - JSON response for programmatic access
   - Rate limiting

6. **Performance**:
   - Full-text search indexes (pg_trgm)
   - Search caching
   - Pagination for >500 results

## Deployment

### Copy Files to Server

From your local machine:
```bash
# Copy source files
scp src/routes/edls.js user@server:/opt/edl-manager-deploy/src/routes/

# Copy view files
scp views/search.ejs user@server:/opt/edl-manager-deploy/views/
scp views/partials/header.ejs user@server:/opt/edl-manager-deploy/views/partials/
scp views/edl.ejs user@server:/opt/edl-manager-deploy/views/
```

### Install on Server

```bash
# Copy to application directory
sudo cp -r /opt/edl-manager-deploy/src/* /opt/EDLManager/src/
sudo cp -r /opt/edl-manager-deploy/views/* /opt/EDLManager/views/

# Fix permissions
sudo chown -R edlmgr:edlmgr /opt/EDLManager

# Restart service
sudo systemctl restart edlmanager

# Verify
sudo systemctl status edlmanager
sudo journalctl -u edlmanager -n 20
```

### Test

1. Open `https://example.com/edl`
2. Log in
3. Notice the search box in the header
4. Type a search term and press Enter
5. Verify results appear correctly
6. Click "view" on a result to verify it jumps to the entry

## Troubleshooting

### Search box doesn't appear
- Check that you're logged in (search is only visible to authenticated users)
- Clear browser cache and hard refresh (Ctrl+Shift+R)

### Search returns no results but entries exist
- Verify the search term (try broader terms)
- Check that EDLs are enabled and have entries
- Check application logs: `sudo journalctl -u edlmanager -f`

### "view" link doesn't jump to entry
- Ensure `views/edl.ejs` has been updated with `id="entry-<%= e.id %>"`
- Check browser console for JavaScript errors
- Verify smooth scrolling CSS is loaded

### Performance issues with large datasets
- Consider adding database indexes (see Performance Considerations above)
- Reduce result limit in `src/routes/edls.js` (currently 500)
- Add pagination for result sets

## Security Considerations

- ✅ **Authentication required**: Search is only available to logged-in users
- ✅ **SQL injection protected**: Uses parameterized queries
- ✅ **No sensitive data exposure**: Search results respect EDL permissions
- ✅ **Rate limiting**: Consider adding if needed (not currently implemented)

## Support

For issues or questions:
1. Check application logs: `sudo journalctl -u edlmanager -f`
2. Review this documentation
3. Check the main README: `README.md`
